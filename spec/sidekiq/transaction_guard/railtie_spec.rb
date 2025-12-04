require "spec_helper"
require "rails"
require "sidekiq/transaction_guard/railtie"

RSpec.describe Sidekiq::TransactionGuard::Railtie do
  before do
    # Reset Sidekiq middleware
    Sidekiq.configure_client do |config|
      config.client_middleware.clear
    end

    Sidekiq::TransactionGuard.mode = :stderr
  end

  describe "initializer" do
    def run_initializer
      described_class.initializers.each(&:run)
    end

    it "sets mode to :error in development" do
      Rails.env = "development"

      run_initializer

      expect(Sidekiq::TransactionGuard.mode).to eq(:error)
    end

    it "sets mode to :error in test" do
      Rails.env = "test"

      run_initializer

      expect(Sidekiq::TransactionGuard.mode).to eq(:error)
    end

    it "sets mode to :warn in production" do
      Rails.env = "production"

      run_initializer

      expect(Sidekiq::TransactionGuard.mode).to eq(:warn)
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
