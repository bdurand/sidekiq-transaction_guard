# frozen_string_literal: true

require "active_record"
require "sidekiq"
require "set"

require_relative "transaction_guard/middleware"

module Sidekiq
  module TransactionGuard
    class InsideTransactionError < StandardError
    end

    @lock = Mutex.new
    @connection_classes = Set.new
    @notify = nil
    @mode = :warn
    @testing_context = false

    class << self
      VALID_MODES = [:warn, :stderr, :error, :disabled].freeze

      # Initialize Sidekiq::TransactionGuard by adding its client middleware to
      # Sidekiq. The middleware is added to both the client and server
      # configurations since jobs can also be enqueued from within other jobs
      # running in the Sidekiq server process.
      #
      # @param mode [Symbol, nil] optionally set the global mode (see `mode=`)
      # @return [void]
      def init(mode: nil)
        self.mode = mode if mode

        Sidekiq.configure_client do |config|
          add_client_middleware(config)
        end

        Sidekiq.configure_server do |config|
          add_client_middleware(config)
        end
      end

      # Set the global mode to one of `[:warn, :stderr, :error, :disabled]`. The
      # default mode is `:warn`. This controls the behavior of workers enqueued
      # inside of transactions.
      # * :warn - Log to Sidekiq.logger
      # * :stderr - Log to STDERR
      # * :error - Raise a `Sidekiq::TransactionGuard::InsideTransactionError`
      # * :disabled - Allow workers inside of transactions
      #
      # @param symbol [Symbol] one of `:warn`, `:stderr`, `:error`, or `:disabled`
      # @return [Symbol] the mode that was set
      def mode=(symbol)
        if VALID_MODES.include?(symbol)
          @lock.synchronize { @mode = symbol }
        else
          raise ArgumentError.new("mode must be one of #{VALID_MODES.inspect}")
        end
      end

      # Return the mode in effect for the current thread. This is the thread local
      # mode if one has been set, otherwise the global mode.
      #
      # @return [Symbol]
      def mode
        thread_local_mode || default_mode
      end

      # Return the globally configured mode, ignoring any thread local override.
      #
      # @return [Symbol]
      def default_mode
        @lock.synchronize { @mode }
      end

      # Set a mode override for the current thread only. This is used by `disable`
      # and the test integrations so that changing the mode in one thread cannot
      # affect jobs being enqueued concurrently in other threads. Set to `nil` to
      # remove the override and fall back to the global mode.
      #
      # @param symbol [Symbol, nil] one of `:warn`, `:stderr`, `:error`, `:disabled`, or nil
      # @return [Symbol, nil] the mode that was set
      def thread_local_mode=(symbol)
        if symbol.nil? || VALID_MODES.include?(symbol)
          Thread.current[:sidekiq_transaction_guard_mode] = symbol
        else
          raise ArgumentError.new("mode must be one of #{VALID_MODES.inspect}")
        end
      end

      # Return the mode override for the current thread, or nil if none is set.
      #
      # @return [Symbol, nil]
      def thread_local_mode
        Thread.current[:sidekiq_transaction_guard_mode]
      end

      # Define the global notify block. This block will be called with a Sidekiq
      # job hash for all jobs enqueued inside transactions if the mode is `:warn`
      # or `:stderr`.
      #
      # @yield [Hash] the Sidekiq job hash
      # @return [void]
      def notify(&block)
        @lock.synchronize { @notify = block }
      end

      # Return the block set as the notify handler with a call to `notify`.
      #
      # @return [Proc, nil] the notify block, or nil if none has been set
      def notify_block
        @lock.synchronize { @notify }
      end

      # Add a class that maintains its own connection pool to the connections
      # being monitored for open transactions. You don't need to add `ActiveRecord::Base`
      # or subclasses. Only the base class that establishes a new connection pool
      # with a call to `establish_connection` needs to be added.
      #
      # @param connection_class [Class] an ActiveRecord model class with its own connection pool
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
          connection = active_connection(connection_class)
          next false unless connection

          connection.open_transactions > allowed_transaction_level(connection_class) &&
            application_transaction_open?(connection)
        end
      end

      # Disable the transaction guard within the provided block. This is useful in test environments when you want to
      # setup data for your tests without worrying about transaction levels.
      #
      # The guard is only disabled for the current thread so that jobs enqueued
      # concurrently in other threads are still checked.
      #
      # @yield the block to execute with the transaction guard disabled
      # @return [Object] the return value of the block
      def disable
        save_mode = thread_local_mode
        begin
          self.thread_local_mode = :disabled
          yield
        ensure
          self.thread_local_mode = save_mode
        end
      end

      # This method call needs to be wrapped around tests that use transactional fixtures.
      # It sets up data structures used to track the number of open transactions.
      # The current transaction level is automatically captured as the baseline so that
      # any transactions opened by test setup (e.g. transactional fixtures) are ignored.
      #
      # @yield the test block to execute
      # @return [Object] the return value of the block
      def testing
        saved_state = begin_testing
        begin
          set_allowed_transaction_level(:all)
          yield
        ensure
          end_testing(saved_state)
        end
      end

      # Start a testing context on the current thread without a block. This is used
      # by test framework integrations (like the Minitest helper) that cannot wrap
      # the entire test in a single block. Use `testing` instead whenever a block
      # can be used. The returned state must be passed to `end_testing` when the
      # test finishes.
      #
      # This method only allocates the transaction tracking state; it does not
      # capture a transaction level baseline. The caller is responsible for calling
      # `set_allowed_transaction_level` once any setup that opens transactions
      # (e.g. transactional fixtures) has run.
      #
      # @api private
      # @return [Object] opaque saved state to pass to `end_testing`
      def begin_testing
        var = :sidekiq_rails_transaction_guard
        saved_state = Thread.current[var]
        Thread.current[var] = (saved_state ? saved_state.dup : {})
        @testing_context = true
        saved_state
      end

      # End a testing context started with `begin_testing`.
      #
      # @api private
      # @param saved_state [Object] the state returned by `begin_testing`
      # @return [void]
      def end_testing(saved_state)
        Thread.current[:sidekiq_rails_transaction_guard] = saved_state
      end

      # This method needs to be called to set the allowed transaction level for a connection
      # class (see `add_connection_class` for more info). The current transaction level
      # for that class's connection will be set as the zero point. This method can only
      # be called inside a block wrapped with the `testing` method.
      #
      # @param connection_classes [Class, Array<Class>, Symbol] the connection class(es) to set the allowed
      #   transaction level for. If `:all` is provided, set the allowed transaction level
      #   for all connection classes set via `add_connection_class`.
      # @param base_transaction_level [Integer] if provided, increment the allowed transaction level
      #   by this amount. This is used when using transactional fixtures to ignore the transaction
      #   opened within the test setup.
      # @return [void]
      def set_allowed_transaction_level(connection_classes, base_transaction_level = 0)
        connection_counts = Thread.current[:sidekiq_rails_transaction_guard]
        unless connection_counts
          raise("set_allowed_transaction_level is only allowed inside a testing block")
        end

        connection_classes = self.connection_classes if connection_classes == :all
        Array(connection_classes).each do |connection_class|
          class_count = begin
            lease_connection(connection_class).open_transactions + base_transaction_level
          rescue ActiveRecord::ConnectionNotEstablished
            base_transaction_level
          end
          connection_counts[connection_class.name] = class_count
        end
      end

      private

      def allowed_transaction_level(connection_class)
        connection_counts = Thread.current[:sidekiq_rails_transaction_guard]
        (connection_counts && connection_counts[connection_class.name]) || 0
      end

      # Return true if the connection has any open transaction that was not opened by
      # the connection pool pinning machinery (Rails 7.2+). Transactional tests pin a
      # connection and wrap it in a non-joinable transaction that the pool then shares
      # with every thread. Those wrapper transactions are test scaffolding, not
      # application transactions, so they never count against the guard. The pin state
      # is read from the pool rather than from a thread local so that threads without a
      # baseline (e.g. web server threads in system tests) get the correct level.
      def application_transaction_open?(connection)
        return true unless @testing_context
        return true unless connection.respond_to?(:pinned)

        # The pool changes the pin state under the connection lock. Hold it so the
        # transaction count and the pin state cannot be read from different states.
        connection.lock.synchronize do
          next true unless connection.pinned

          open_transactions = connection.open_transactions
          open_transactions > pinned_transaction_count(connection, open_transactions)
        end
      end

      # Return the number of open transactions on a pinned connection that belong to
      # the pinning machinery. The pool counts pins rather than transactions, so the
      # count is only trusted as far as the connection state supports it: it can never
      # exceed the open transactions, and if it accounts for all of them then the
      # innermost one must be non-joinable, since the wrappers always are. Anything
      # else means the wrappers were closed outside of the pinning machinery and
      # nothing should be discounted.
      def pinned_transaction_count(connection, open_transactions)
        depth = connection.pool.instance_variable_get(:@pinned_connections_depth).to_i
        depth = open_transactions if depth > open_transactions
        return 0 if depth == open_transactions && connection.current_transaction.joinable?

        depth
      end

      def add_client_middleware(config)
        config.client_middleware do |chain|
          unless chain.exists?(Sidekiq::TransactionGuard::Middleware)
            chain.add Sidekiq::TransactionGuard::Middleware
          end
        end
      end

      # Return the connection for the class only if the current thread already has
      # one checked out. Checking out a new connection here would be pointless (a
      # freshly checked out connection can't be inside an application transaction)
      # and would tie up connections from pools the code isn't even using.
      def active_connection(connection_class)
        connection = nil
        pool = connection_class.connection_pool
        connection = lease_connection(connection_class) if pool.active_connection?
        connection
      rescue ActiveRecord::ConnectionNotEstablished
        nil
      end

      def lease_connection(connection_class)
        if connection_class.respond_to?(:lease_connection)
          connection_class.lease_connection
        else
          connection_class.connection
        end
      end
    end
  end
end

if defined?(Rails::Railtie)
  require_relative "transaction_guard/railtie"
end

# Configure the default transaction guard mode for known testing environments.
# In a Rails application the Railtie initializer will override this default.
if ENV["RAILS_ENV"] == "test" || ENV["RACK_ENV"] == "test"
  Sidekiq::TransactionGuard.mode = :stderr
end
