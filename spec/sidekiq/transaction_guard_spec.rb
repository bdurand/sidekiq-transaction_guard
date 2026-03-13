# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sidekiq::TransactionGuard do
  describe ".init" do
    around do |example|
      mode = Sidekiq::TransactionGuard.mode
      begin
        # Reset Sidekiq middleware
        Sidekiq.configure_client do |config|
          config.client_middleware.clear
        end
        example.run
      ensure
        Sidekiq::TransactionGuard.mode = mode
      end
    end

    it "adds the middleware to Sidekiq client middleware" do
      Sidekiq::TransactionGuard.init

      chain = nil
      Sidekiq.configure_client do |config|
        chain = config.client_middleware
      end
      expect(chain.exists?(Sidekiq::TransactionGuard::Middleware)).to be(true)

      expect(Sidekiq::TransactionGuard.mode).to eq(:error)
    end

    it "sets the mode if provided" do
      Sidekiq::TransactionGuard.init(mode: :warn)

      expect(Sidekiq::TransactionGuard.mode).to eq(:warn)
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
