# frozen_string_literal: true

require "spec_helper"

RSpec.describe "rspec integration" do
  it "detects transactions in test code" do
    ActiveRecord::Base.transaction do
      expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
    end
  end

  it "is not in a transaction by default" do
    expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
  end

  it "can change the mode for examples", sidekiq_transaction_guard: :stderr do
    expect(Sidekiq::TransactionGuard.mode).to eq :stderr
  end

  it "runs examples in :error mode by default" do
    expect(Sidekiq::TransactionGuard.mode).to eq :error
  end

  it "can disable the guard for examples", sidekiq_transaction_guard: false do
    expect(Sidekiq::TransactionGuard.mode).to eq :disabled
  end

  it "uses the global mode when tagged with :default", sidekiq_transaction_guard: :default do
    expect(Sidekiq::TransactionGuard.mode).to eq Sidekiq::TransactionGuard.default_mode
  end

  it "does not change the global mode" do
    expect(Sidekiq::TransactionGuard.default_mode).to eq :warn
    expect(Sidekiq::TransactionGuard.thread_local_mode).to eq :error
  end

  describe "snapshot timing" do
    # Group level before hooks registered by the integration run before hooks
    # declared in the group body, so a transaction opened here is detected.
    before do
      @before_hook_in_transaction = TestModel.transaction do
        Sidekiq::TransactionGuard.in_transaction?
      end
    end

    it "takes the transaction snapshot before hooks declared in the group" do
      expect(@before_hook_in_transaction).to eq true
    end
  end
end
