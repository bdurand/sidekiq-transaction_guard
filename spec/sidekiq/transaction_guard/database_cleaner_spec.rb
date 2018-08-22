require 'spec_helper'

begin
  require 'database_cleaner'
rescue LoadError
  STDERR.puts("DatabaseCleaner not available; specs not run")
end

DatabaseCleaner.orm = :active_record

require 'sidekiq/transaction_guard/database_cleaner'

describe Sidekiq::TransactionGuard::DatabaseCleaner do
  it "should not count the wrapping transaction in determining if a transaction is open" do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.cleaning do
      expect(ActiveRecord::Base.connection.open_transactions).to eq 1
      expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
      TestModel.transaction do
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
      end
      expect(Sidekiq::TransactionGuard.in_transaction?).to eq false
    end
  end
end
