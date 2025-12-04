# frozen_string_literal: true

require "sidekiq/transaction_guard"
require "database_cleaner/active_record"

module Sidekiq
  module TransactionGuard
    module DatabaseCleaner
      # Override the start method to set the base number of allowed transactions to
      # the current level. Anything above this number will then be considered to be
      # in a transaction.
      #
      # @return [Object] the return value from the superclass's start method
      def start
        retval = super
        Sidekiq::TransactionGuard.set_allowed_transaction_level(connection_class)
        retval
      end

      # Wrap the `Sidekiq::TransactionGuard.testing` method which sets up the data structures
      # needed for custom counting of the transaction level within a test block.
      #
      # @yield the cleaning block to execute
      # @return [Object] the return value of the block
      def cleaning(&block)
        Sidekiq::TransactionGuard.testing { super(&block) }
      end
    end
  end
end

::DatabaseCleaner::ActiveRecord::Transaction.send(:prepend, Sidekiq::TransactionGuard::DatabaseCleaner)
