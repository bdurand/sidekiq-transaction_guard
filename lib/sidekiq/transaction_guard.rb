# frozen_string_literal: true

require "sidekiq"
require "set"

require_relative "transaction_guard/middleware"

if defined?(Rails::Railtie)
  require_relative "transaction_guard/railtie"
end

module Sidekiq
  module TransactionGuard
    class InsideTransactionError < StandardError
    end

    @lock = Mutex.new
    @connection_classes = Set.new
    @notify = nil
    @mode = :warn

    class << self
      VALID_MODES = [:warn, :stderr, :error, :disabled].freeze

      # Set the global mode to one of `[:warn, :stderr, :error, :disabled]`. The
      # default mode is `:warn`. This controls the behavior of workers enqueued
      # inside of transactions.
      # * :warn - Log to Sidekiq.logger
      # * :stderr - Log to STDERR
      # * :error - Throw a `Sidekiq::TransactionGuard::InsideTransactionError`
      # * :disabled - Allow workers inside of transactions
      #
      # @param mode [Symbol]
      # @return [void]
      def mode=(symbol)
        if VALID_MODES.include?(symbol)
          @mode = symbol
        else
          raise ArgumentError.new("mode must be one of #{VALID_MODES.inspect}")
        end
      end

      # Return the current mode.
      #
      # @return [Symbol]
      attr_reader :mode

      # Define the global notify block. This block will be called with a Sidekiq
      # job hash for all jobs enqueued inside transactions if the mode is `:warn`
      # or `:stderr`.
      #
      # @return [void]
      def notify(&block)
        @notify = block
      end

      # Return the block set as the notify handler with a call to `notify`.
      #
      # @return [Proc]
      def notify_block
        @notify
      end

      # Add a class that maintains it's own connection pool to the connections
      # being monitored for open transactions. You don't need to add `ActiveRecord::Base`
      # or subclasses. Only the base class that establishes a new connection pool
      # with a call to `establish_connection` needs to be added.
      #
      # @param connection_class [Class]
      # @return [void]
      def add_connection_class(connection_class)
        @lock.synchronize { @connection_classes << connection_class }
      end

      # Return the classes that have been added via `add_connection_class`.
      #
      # @return [Array<Class>]
      def connection_classes
        ([ActiveRecord::Base] + @lock.synchronize { @connection_classes.to_a }).uniq
      end

      # Return true if any connection is currently inside of a transaction.
      #
      # @return [Boolean]
      def in_transaction?
        connection_classes.any? do |connection_class|
          connection_pool = connection_class.connection_pool
          connection = connection_class.connection if connection_pool.active_connection?
          if connection
            connection.open_transactions > allowed_transaction_level(connection_class)
          else
            false
          end
        end
      end

      # This method call needs to be wrapped around tests that use transactional fixtures.
      # It sets up data structures used to track the number of open transactions.
      #
      # @return [Object] the return value of the block
      def testing(&block)
        var = :sidekiq_rails_transaction_guard
        save_val = Thread.current[var]
        begin
          Thread.current[var] = (save_val ? save_val.dup : {})
          yield
        ensure
          Thread.current[var] = save_val
        end
      end

      # This method needs to be called to set the allowed transaction level for a connection
      # class (see `add_connection_class` for more info). The current transaction level
      # for that class' connection will be set as the zero point. This method can only
      # be called inside a block wrapped with the `testing` method.
      #
      # @param connection_classes [Class, Array<Class>, :all] the connection class to set the allowed
      #   transaction level for. If `:all` is provided, set the allowed transaction level
      #   for all connection classes set via `add_connection_class`.
      # @param count [Integer, nil] if provided, set the allowed transaction level to this
      #   value instead of the current transaction count. Use this if you cannot add the
      #   hook in the correct spot in your test setup. ActiveRecord transactional fixtures
      #   require this to be set while DatabaseCleaner will grab it dynamically.
      # @return [void]
      def set_allowed_transaction_level(connection_classes, count = nil)
        connection_counts = Thread.current[:sidekiq_rails_transaction_guard]
        unless connection_counts
          raise("set_allowed_transaction_level is only allowed inside a testing block")
        end

        connection_classes = self.connection_classes if connection_classes == :all
        Array(connection_classes).each do |connection_class|
          class_count = count || connection_class.connection.open_transactions
          connection_counts[connection_class.name] = class_count
        end
      end

      private

      def allowed_transaction_level(connection_class)
        connection_counts = Thread.current[:sidekiq_rails_transaction_guard]
        (connection_counts && connection_counts[connection_class.name]) || 0
      end
    end
  end
end

# Configure the default transaction guard mode for known testing environments.
if ENV["RAILS_ENV"] == "test" || ENV["RACK_ENV"] == "test"
  Sidekiq::TransactionGuard.mode = :stderr
end
