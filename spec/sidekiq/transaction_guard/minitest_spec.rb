# frozen_string_literal: true

require "spec_helper"
require "minitest"
require "minitest/spec"
require "sidekiq/transaction_guard/minitest"

RSpec.describe "minitest integration" do
  it "captures the current transaction level as the base", sidekiq_transaction_guard: :default do
    original_mode = Sidekiq::TransactionGuard.mode

    saved_mode = Sidekiq::TransactionGuard.mode
    Sidekiq::TransactionGuard.mode = :error

    # Simulate transactional fixture already being open
    ActiveRecord::Base.transaction do
      Sidekiq::TransactionGuard.testing do
        expect(Sidekiq::TransactionGuard.mode).to eq :error

        # The fixture transaction is captured as the base, so should not detect it
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq false

        # But a transaction on a different registered connection should be detected
        OtherConnectionModel.transaction do
          expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
        end
      end
    end

    Sidekiq::TransactionGuard.mode = saved_mode
    expect(Sidekiq::TransactionGuard.mode).to eq original_mode
  end

  it "works without transactional fixtures", sidekiq_transaction_guard: :default do
    original_mode = Sidekiq::TransactionGuard.mode

    saved_mode = Sidekiq::TransactionGuard.mode
    Sidekiq::TransactionGuard.mode = :error

    Sidekiq::TransactionGuard.testing do
      expect(Sidekiq::TransactionGuard.mode).to eq :error

      # Should detect transaction when no fixture transaction is open
      ActiveRecord::Base.transaction do
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
      end
    end

    Sidekiq::TransactionGuard.mode = saved_mode
    expect(Sidekiq::TransactionGuard.mode).to eq original_mode
  end
end
