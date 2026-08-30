# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sidekiq::TransactionGuard do
  describe ".init" do
    around do |example|
      mode = Sidekiq::TransactionGuard.default_mode
      begin
        # Reset Sidekiq middleware
        Sidekiq.configure_client do |config|
          config.client_middleware.clear
        end
        example.run
      ensure
        Sidekiq::TransactionGuard.mode = mode
        Sidekiq.configure_client do |config|
          config.client_middleware.clear
        end
      end
    end

    it "adds the middleware to Sidekiq client middleware without changing the mode" do
      mode = Sidekiq::TransactionGuard.default_mode

      Sidekiq::TransactionGuard.init

      chain = nil
      Sidekiq.configure_client do |config|
        chain = config.client_middleware
      end
      expect(chain.exists?(Sidekiq::TransactionGuard::Middleware)).to be(true)

      expect(Sidekiq::TransactionGuard.default_mode).to eq(mode)
    end

    it "adds the client middleware to the server configuration" do
      allow(Sidekiq).to receive(:server?).and_return(true)

      Sidekiq::TransactionGuard.init

      chain = nil
      Sidekiq.configure_server do |config|
        chain = config.client_middleware
      end
      expect(chain.exists?(Sidekiq::TransactionGuard::Middleware)).to be(true)
    end

    it "sets the mode if provided" do
      Sidekiq::TransactionGuard.init(mode: :stderr)

      expect(Sidekiq::TransactionGuard.default_mode).to eq(:stderr)
    end
  end

  describe "mode" do
    it "should default to :warn and be able to be set to :error", sidekiq_transaction_guard: :default do
      mode = Sidekiq::TransactionGuard.mode
      begin
        expect(Sidekiq::TransactionGuard.mode).to eq :warn
        Sidekiq::TransactionGuard.mode = :error
        expect(Sidekiq::TransactionGuard.mode).to eq :error
      ensure
        Sidekiq::TransactionGuard.mode = mode
      end
    end

    it "should not allow invalid modes" do
      expect { Sidekiq::TransactionGuard.mode = :bogus }.to raise_error(ArgumentError)
    end
  end

  describe "thread_local_mode" do
    it "overrides the global mode only in the current thread", sidekiq_transaction_guard: :default do
      expect(Sidekiq::TransactionGuard.mode).to eq :warn
      begin
        Sidekiq::TransactionGuard.thread_local_mode = :stderr
        expect(Sidekiq::TransactionGuard.mode).to eq :stderr
        expect(Sidekiq::TransactionGuard.default_mode).to eq :warn
        expect(Thread.new { Sidekiq::TransactionGuard.mode }.value).to eq :warn
      ensure
        Sidekiq::TransactionGuard.thread_local_mode = nil
      end
      expect(Sidekiq::TransactionGuard.mode).to eq :warn
    end

    it "should not allow invalid modes" do
      expect { Sidekiq::TransactionGuard.thread_local_mode = :bogus }.to raise_error(ArgumentError)
    end
  end

  describe "in_transaction?" do
    it "should not be in transaction by default" do
      expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
    end

    it "should be in a transaction if any registered connection is in a transaction" do
      TestModel.transaction do
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
      end
      expect(Sidekiq::TransactionGuard.in_transaction?).to eq false

      OtherConnectionModel.transaction do
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
      end
      expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
    end

    it "should not be in a transaction if only an unregistered connection is in a transaction" do
      UnregisteredConnectionModel.transaction do
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
      end
      expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
    end

    describe "with a pinned connection" do
      def with_pinned_connection(pool)
        pool.pin_connection!(false)
        begin
          yield
        ensure
          pool.unpin_connection!
        end
      end

      # Check the transaction state from a thread that shares the pinned
      # connection but has no thread local baseline, like a web server thread
      # in a system test.
      def in_transaction_from_new_thread?(model_class)
        Thread.new do
          model_class.lease_connection
          begin
            Sidekiq::TransactionGuard.in_transaction?
          ensure
            model_class.release_connection
          end
        end.value
      end

      before do
        unless ActiveRecord::Base.connection_pool.respond_to?(:pin_connection!)
          skip "connection pinning requires ActiveRecord 7.2+"
        end
      end

      it "should not count the pinned wrapper transaction on the test thread" do
        with_pinned_connection(TestModel.connection_pool) do
          expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
        end
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
      end

      it "should not count the pinned wrapper transaction on threads without a baseline" do
        with_pinned_connection(TestModel.connection_pool) do
          expect(in_transaction_from_new_thread?(TestModel)).to eq false
        end
      end

      it "should not count nested pinned wrapper transactions" do
        pool = TestModel.connection_pool
        with_pinned_connection(pool) do
          with_pinned_connection(pool) do
            expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
            expect(in_transaction_from_new_thread?(TestModel)).to eq false
          end
        end
      end

      it "should count application transactions opened under the pinned wrapper from any thread" do
        with_pinned_connection(TestModel.connection_pool) do
          TestModel.transaction do
            expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
            expect(in_transaction_from_new_thread?(TestModel)).to eq true
          end
          expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
        end
      end

      it "should count application transactions opened with joinable: false" do
        with_pinned_connection(TestModel.connection_pool) do
          TestModel.transaction(joinable: false, requires_new: true) do
            expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
            expect(in_transaction_from_new_thread?(TestModel)).to eq true
          end
        end
      end
    end
  end

  describe ".disable" do
    it "should disable transaction guarding within the block" do
      Sidekiq::TransactionGuard.disable do
        expect(Sidekiq::TransactionGuard.mode).to eq :disabled
        Sidekiq::TransactionGuard.testing do
          expect(Sidekiq::TransactionGuard.mode).to eq :disabled
        end
      end
      expect(Sidekiq::TransactionGuard.mode).to eq :error
    end

    it "should not disable transaction guarding in other threads", sidekiq_transaction_guard: :default do
      Sidekiq::TransactionGuard.disable do
        expect(Sidekiq::TransactionGuard.mode).to eq :disabled
        expect(Thread.new { Sidekiq::TransactionGuard.mode }.value).to eq :warn
      end
    end
  end

  describe ".testing" do
    it "can reset the allowed transaction levels in a block" do
      TestModel.transaction do
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq true

        Sidekiq::TransactionGuard.testing do
          expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
        end

        expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
      end
    end

    it "automatically captures the current transaction level as the base" do
      TestModel.transaction do
        OtherConnectionModel.transaction do
          Sidekiq::TransactionGuard.testing do
            expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
          end
        end
      end
    end
  end
end
