# frozen_string_literal: true

require "spec_helper"
require "minitest"
require "minitest/spec"
require "sidekiq/transaction_guard/minitest"

RSpec.describe "minitest integration" do
  it "works with ActiveSupport::TestCase", sidekiq_transaction_guard: :default do
    # Save original mode
    original_mode = Sidekiq::TransactionGuard.mode

    # Simulate what happens in a minitest setup with transactional tests
    saved_mode = Sidekiq::TransactionGuard.mode
    Sidekiq::TransactionGuard.mode = :error

    Sidekiq::TransactionGuard.testing(base_transaction_level: 1) do
      expect(Sidekiq::TransactionGuard.mode).to eq :error

      # In a transaction, but base level is 1, so should not detect it
      ActiveRecord::Base.transaction do
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
      end
    end

    # Simulate teardown
    Sidekiq::TransactionGuard.mode = saved_mode

    # Verify mode was restored
    expect(Sidekiq::TransactionGuard.mode).to eq original_mode
  end

  it "works without transactional tests", sidekiq_transaction_guard: :default do
    original_mode = Sidekiq::TransactionGuard.mode

    saved_mode = Sidekiq::TransactionGuard.mode
    Sidekiq::TransactionGuard.mode = :error

    Sidekiq::TransactionGuard.testing(base_transaction_level: 0) do
      expect(Sidekiq::TransactionGuard.mode).to eq :error

      # Should detect transaction when base level is 0
      ActiveRecord::Base.transaction do
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
      end
    end

    Sidekiq::TransactionGuard.mode = saved_mode

    expect(Sidekiq::TransactionGuard.mode).to eq original_mode
  end
end
