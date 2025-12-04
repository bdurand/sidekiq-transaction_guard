# frozen_string_literal: true

require "spec_helper"

RSpec.describe "rspec integration" do
  context "with transactional tests" do
    def use_transactional_tests
      true
    end

    it "ignores the outermost transaction" do
      ActiveRecord::Base.transaction do
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
      end
    end
  end

  context "without transactional tests" do
    def use_transactional_tests
      false
    end

    it "detects the outermost transaction" do
      ActiveRecord::Base.transaction do
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
      end
    end
  end

  it "can change the mode for examples", sidekiq_transaction_guard: :stderr do
    expect(Sidekiq::TransactionGuard.mode).to eq :stderr
  end
end
