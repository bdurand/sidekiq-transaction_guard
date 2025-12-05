# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sidekiq::TransactionGuard do
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
  end

  describe ".testing" do
    it "can reset the allowed transaction levels in a block" do
      TestModel.transaction do
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq true

        Sidekiq::TransactionGuard.testing do
          expect(Sidekiq::TransactionGuard.in_transaction?).to eq true

          Sidekiq::TransactionGuard.set_allowed_transaction_level(:all)
          expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
        end

        expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
      end
    end

    it "can set a base transaction level to ignore outer transactions" do
      TestModel.transaction do
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq true

        Sidekiq::TransactionGuard.testing(base_transaction_level: 1) do
          expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
        end

        expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
      end
    end
  end
end
