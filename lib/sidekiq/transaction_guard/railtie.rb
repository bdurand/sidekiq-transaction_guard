# frozen_string_literal: true

module Sidekiq::TransactionGuard
  class Railtie < ::Rails::Railtie
    initializer "sidekiq.transaction_guard" do
      mode = (Rails.env.development? || Rails.env.test?) ? :error : :warn
      Sidekiq::TransactionGuard.init(mode: mode)
    end
  end
end
