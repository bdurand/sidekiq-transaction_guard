# frozen_string_literal: true

RSpec.configure do |config|
  global_sidekiq_transaction_guard_mode = nil

  # Disable by default to avoid raising errors in test setup and teardown.
  config.before(:suite) do
    global_sidekiq_transaction_guard_mode = Sidekiq::TransactionGuard.mode
    Sidekiq::TransactionGuard.mode = :disabled
  end

  config.after(:suite) do
    Sidekiq::TransactionGuard.mode = global_sidekiq_transaction_guard_mode
  end

  config.around do |example|
    mode = example.metadata[:sidekiq_transaction_guard]
    mode = :disabled if mode == false
    mode = global_sidekiq_transaction_guard_mode if mode == :default
    mode = :error unless mode.is_a?(Symbol)

    save_val = Sidekiq::TransactionGuard.mode
    begin
      Sidekiq::TransactionGuard.mode = mode
      Sidekiq::TransactionGuard.testing do
        example.run
      end
    ensure
      Sidekiq::TransactionGuard.mode = save_val
    end
  end

  # Re-snapshot the allowed transaction level after all setup (including
  # transactional fixtures) has run so that setup transactions are ignored.
  config.before(:each) do
    Sidekiq::TransactionGuard.set_allowed_transaction_level(:all)
  end
end
