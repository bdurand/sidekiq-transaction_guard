# frozen_string_literal: true

require "spec_helper"

describe Sidekiq::TransactionGuard do
  describe "mode" do
    it "should default to :warn and be able to be set to :error" do
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
end
