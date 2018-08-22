# frozen_string_literal: true

require 'sidekiq'
require 'set'
require 'thread'
require 'active_record'

require_relative 'sidekiq_transaction_guard/middleware'

module SidekiqTransactionGuard
  class InsideTransactionError < StandardError
  end

  @lock = Mutex.new

  class << self
    VALID_MODES = [:warn, :stderr, :error, :disabled].freeze

    # Set the global mode to one of `[:warn, :stderr, :error, :disabled]`. The
    # default mode is `:warn`. This controls the behavior of workers enqueued
    # inside of transactions.
    # * :warn - Log to Sidekiq.logger
    # * :stderr - Log to $stderr
    # * :error - Throw a `SidekiqTransactionGuard::InsideTransactionError`
    # * :disabled - Allow workers inside of transactions
    def mode=(symbol)
      if VALID_MODES.include?(symbol)
        @mode = symbol
      else
        raise ArgumentError.new("mode must be one of #{VALID_MODES.inspect}")
      end
    end

    # Return the current mode.
    def mode
      @mode
    end

    # Define the global notify block. This block will be called with a Sidekiq
    # job hash for all jobs enqueued inside transactions if the mode is `:warn`
    # or `:stderr`.
    def notify(&block)
      @notify = block
    end

    # Return the block set as the notify handler with a call to `notify`.
    def notify_block
      @notify ||= nil
    end

    # Add a class that maintains it's own connection pool to the connections
    # being monitored for open transactions. You don't need to add `ActiveRecord::Base`
    # or subclasses. Only the base class that establishes a new connection pool
    # with a call to `establish_connection` needs to be added.
    def add_connection_class(connection_class)
      @connection_classes ||= Set.new
      @connection_classes << connection_class
    end

    # Return true if any connection is currently inside of a transaction.
    def in_transaction?
      connection_classes = @lock.synchronize{ @connection_classes.dup }
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
    def set_allowed_transaction_level(connection_class)
      connection_counts = Thread.current[:sidekiq_rails_transaction_guard]
      unless connection_counts
        raise("set_allowed_transaction_level is only allowed inside a testing block")
      end
      connection_counts[connection_class.name] = connection_class.connection.open_transactions if connection_counts
    end

    private

    def allowed_transaction_level(connection_class)
      connection_counts = Thread.current[:sidekiq_rails_transaction_guard]
      (connection_counts && connection_counts[connection_class.name]) || 0
    end
  end
end

# Configure the default transaction guard mode
if ENV["RAILS_ENV"] == "test" || ENV["RACK_ENV"] == "test"
  SidekiqTransactionGuard.mode = :stderr
else
  SidekiqTransactionGuard.mode = :warn
end

# Add the ActiveRecord::Base connection class by default
SidekiqTransactionGuard.add_connection_class(::ActiveRecord::Base)
