require 'spec_helper'

require 'sidekiq/testing'

class TestWorker
  include Sidekiq::Worker

  def perform
  end
end

class TestWithNotifierWorker
  include Sidekiq::Worker

  sidekiq_options notify_in_transaction: -> (job) { self.in_transaction_args = job["args"] }

  class << self
    def in_transaction_args=(val)
      @in_transaction_args = val
    end

    def in_transaction_args
      @in_transaction_args if defined?(@in_transaction_args)
    end
  end

  def perform(arg)
  end
end

class ErrorWorker
  include Sidekiq::Worker

  sidekiq_options in_transaction_mode: :error

  def perform
  end
end

class InTransactionWorker
  include Sidekiq::Worker

  sidekiq_options in_transaction_mode: :allowed

  def perform
  end
end

describe SidekiqTransactionGuard::Middleware do
  before(:all) do
    Sidekiq.configure_client do |config|
      config.client_middleware do |chain|
        chain.add SidekiqTransactionGuard::Middleware
      end
    end
  end

  after(:all) do
    Sidekiq.configure_client do |config|
      config.client_middleware do |chain|
        chain.remove SidekiqTransactionGuard::Middleware
      end
    end
  end

  before(:each) do
    Sidekiq::Worker.clear_all
  end

  describe "outside a transaction" do
    it "should not interfere with scheduling jobs" do
      TestWorker.perform_async
      expect(TestWorker.jobs.size).to eq 1
    end
  end

  describe "inside a transaciton with mode :warn" do
    let(:log){ StringIO.new }

    around(:each) do |example|
      save_mode = SidekiqTransactionGuard.mode
      save_logger = Sidekiq.logger
      begin
        SidekiqTransactionGuard.mode = :warn
        Sidekiq.logger = Logger.new(log)
        example.call
      ensure
        SidekiqTransactionGuard.mode = save_mode
        Sidekiq.logger = save_logger
      end
    end

    it "should log jobs being scheduled inside of a transaction" do
      TestModel.transaction do
        TestWorker.perform_async
      end
      expect(TestWorker.jobs.size).to eq 1
      expect(log.string).to include "TestWorker was called from inside a database transaction"
    end

    it "should call a notify handler with the job if it has been set" do
      TestModel.transaction do
        TestWithNotifierWorker.perform_async("foo")
      end
      expect(TestWithNotifierWorker.jobs.size).to eq 1
      expect(TestWithNotifierWorker.in_transaction_args).to eq ["foo"]
    end

    it "should be able to define the mode on the worker class" do
      TestModel.transaction do
        expect{ ErrorWorker.perform_async }.to raise_error(SidekiqTransactionGuard::InsideTransactionError)
      end
      expect(ErrorWorker.jobs.size).to eq 0
    end
  end

  describe "inside a transaction with mode :stderr" do
    around(:each) do |example|
      save_mode = SidekiqTransactionGuard.mode
      save_stderr = $stderr
      begin
        SidekiqTransactionGuard.mode = :stderr
        $stderr = StringIO.new
        example.call
      ensure
        SidekiqTransactionGuard.mode = save_mode
        $stderr = save_stderr
      end
    end

    it "should report to STDERR" do
      TestModel.transaction do
        TestWorker.perform_async
      end
      expect(TestWorker.jobs.size).to eq 1
      expect($stderr.string).to include "TestWorker was called from inside a database transaction"
    end

    it "should log to STDERR jobs being scheduled inside of a transaction if there is no logger" do
      SidekiqTransactionGuard.mode = :warn
      allow(Sidekiq).to receive(:logger).and_return(nil)
      TestModel.transaction do
        TestWorker.perform_async
      end
      expect(TestWorker.jobs.size).to eq 1
      expect($stderr.string).to include "TestWorker was called from inside a database transaction"
    end
  end

  describe "inside a transaction with mode :error" do
    around(:each) do |example|
      save_mode = SidekiqTransactionGuard.mode
      begin
        SidekiqTransactionGuard.mode = :error
        example.call
      ensure
        SidekiqTransactionGuard.mode = save_mode
      end
    end

    it "should raise an error if job is scheduled inside of a transaction" do
      TestModel.transaction do
        expect{ TestWorker.perform_async }.to raise_error(SidekiqTransactionGuard::InsideTransactionError)
      end
      expect(TestWorker.jobs.size).to eq 0
    end

    it "should raise an error if job is scheduled in the future" do
      TestModel.transaction do
        expect{ TestWorker.perform_in(60) }.to raise_error(SidekiqTransactionGuard::InsideTransactionError)
      end
      expect(TestWorker.jobs.size).to eq 0
    end

    it "should allow jobs to be scheduled if they explicitly are allowed inside transactions" do
      TestModel.transaction do
        InTransactionWorker.perform_async("foo")
      end
      expect(InTransactionWorker.jobs.size).to eq 1
    end
  end
end
