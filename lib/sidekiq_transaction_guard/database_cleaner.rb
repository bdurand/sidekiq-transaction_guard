require 'database_cleaner'
require 'database_cleaner/active_record/transaction'

module SidekiqTransactionGuard
  module DatabaseCleaner
    # Override the start method to set the base number of allowed transactions to
    # the current level. Anything above this number will then be considered to be
    # in a transaction.
    def start
      retval = super
      SidekiqTransactionGuard.set_allowed_transaction_level(connection_class)
      retval
    end

    # Wrap the `SidekiqTransactionGuard.testing` which sets up the data structures
    # needed for custom counting of the transaction level within a test block.
    def cleaning(&block)
      SidekiqTransactionGuard.testing{ super(&block) }
    end
  end
end

::DatabaseCleaner::ActiveRecord::Transaction.send(:prepend, SidekiqTransactionGuard::DatabaseCleaner)
