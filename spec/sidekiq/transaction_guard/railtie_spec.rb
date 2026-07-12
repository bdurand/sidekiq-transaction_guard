# frozen_string_literal: true

require "spec_helper"

require "rails/railtie"
require "sidekiq/transaction_guard/railtie"

RSpec.describe Sidekiq::TransactionGuard::Railtie do
  around do |example|
    saved_mode = Sidekiq::TransactionGuard.default_mode
    saved_env = Rails.env.to_s
    begin
      # Reset Sidekiq middleware
      Sidekiq.configure_client do |config|
        config.client_middleware.clear
      end
      example.run
    ensure
      Sidekiq::TransactionGuard.mode = saved_mode
      Rails.env = saved_env
      Sidekiq.configure_client do |config|
        config.client_middleware.clear
      end
    end
  end

  before do
    Sidekiq::TransactionGuard.mode = :stderr
  end

  describe "initializer" do
    def run_initializer
      described_class.initializers.each(&:run)
    end

    it "sets mode to :error in development" do
      Rails.env = "development"

      run_initializer

      expect(Sidekiq::TransactionGuard.default_mode).to eq(:error)
    end

    it "sets mode to :error in test" do
      Rails.env = "test"

      run_initializer

      expect(Sidekiq::TransactionGuard.default_mode).to eq(:error)
    end

    it "sets mode to :warn in production" do
      Rails.env = "production"

      run_initializer

      expect(Sidekiq::TransactionGuard.default_mode).to eq(:warn)
    end

    it "adds the middleware" do
      Rails.env = "production"

      run_initializer

      chain = nil
      Sidekiq.configure_client do |config|
        chain = config.client_middleware
      end
      expect(chain.exists?(Sidekiq::TransactionGuard::Middleware)).to be(true)
    end
  end
end
