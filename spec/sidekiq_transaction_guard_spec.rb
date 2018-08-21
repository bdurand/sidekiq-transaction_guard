require 'spec_helper'

describe SidekiqTransactionGuard do
  describe "mode" do
    it "should default to :warn and be able to be set to :error" do
      mode = SidekiqTransactionGuard.mode
      begin
        expect(SidekiqTransactionGuard.mode).to eq :warn
        SidekiqTransactionGuard.mode = :error
        expect(SidekiqTransactionGuard.mode).to eq :error
      ensure
        SidekiqTransactionGuard.mode = mode
      end
    end
  end

  describe "in_transaction?" do
    it "should not be in transaction by default" do
      expect(SidekiqTransactionGuard.in_transaction?).to eq false
    end

    it "should be in a transaction if any registered connection is in a transaction" do
      TestModel.transaction do
        expect(SidekiqTransactionGuard.in_transaction?).to eq true
      end
      expect(SidekiqTransactionGuard.in_transaction?).to eq false

      OtherConnectionModel.transaction do
        expect(SidekiqTransactionGuard.in_transaction?).to eq true
      end
      expect(SidekiqTransactionGuard.in_transaction?).to eq false
    end

    it "should not be in a transaction if only an unregistered connection is in a transaction" do
      UnregisteredConnectionModel.transaction do
        expect(SidekiqTransactionGuard.in_transaction?).to eq false
      end
      expect(SidekiqTransactionGuard.in_transaction?).to eq false
    end
  end
end
