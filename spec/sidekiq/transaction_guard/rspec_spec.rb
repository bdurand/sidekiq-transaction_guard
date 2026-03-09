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
end
