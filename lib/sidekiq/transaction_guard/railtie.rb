# frozen_string_literal: true

module Sidekiq::TransactionGuard
  class Railtie < ::Rails::Railtie
    initializer "sidekiq.transaction_guard" do
      Sidekiq::TransactionGuard.mode = (Rails.env.development? || Rails.env.test? ? :error : :warn)

      Sidekiq.configure_client do |config|
        config.client_middleware do |chain|
          chain.add Sidekiq::TransactionGuard::Middleware
        end
      end
    end
  end
end
