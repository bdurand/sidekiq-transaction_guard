# frozen_string_literal: true

require "minitest"

require "sidekiq/transaction_guard"

module Sidekiq
  module TransactionGuard
    # Minitest helper module for testing with Sidekiq::TransactionGuard.
    #
    # Include this module in your test class to automatically set up transaction
    # tracking for each test. If `ActiveSupport::TestCase` is defined when this
    # file is required, the module is included there automatically.
    #
    # The integration uses Minitest's `before_setup`/`after_teardown` lifecycle
    # hooks. The transaction level snapshot is taken after all other setup hooks
    # have run (including transactional fixtures), so transactions opened by test
    # setup are ignored, and the snapshot stays in effect for the entire test.
    # The guard runs in `:error` mode during the test and is disabled while
    # setup and teardown hooks run.
    #
    # @example
    #   class MyTest < Minitest::Test
    #     include Sidekiq::TransactionGuard::MinitestHelper
    #
    #     def test_something
    #       # Test code here
    #     end
    #   end
    module MinitestHelper
      def before_setup
        @sidekiq_transaction_guard_saved_mode = Sidekiq::TransactionGuard.thread_local_mode
        @sidekiq_transaction_guard_saved_state = Sidekiq::TransactionGuard.begin_testing
        # Keep the guard disabled while other before_setup hooks (like
        # transactional fixtures) and setup callbacks run.
        Sidekiq::TransactionGuard.thread_local_mode = :disabled
        super
        # Take the snapshot now that all other setup hooks have run so that
        # transactions opened during setup are treated as the baseline.
        Sidekiq::TransactionGuard.set_allowed_transaction_level(:all)
        Sidekiq::TransactionGuard.thread_local_mode = :error
      end

      def before_teardown
        Sidekiq::TransactionGuard.thread_local_mode = :disabled
        super
      end

      def after_teardown
        super
      ensure
        if defined?(@sidekiq_transaction_guard_saved_state)
          Sidekiq::TransactionGuard.end_testing(@sidekiq_transaction_guard_saved_state)
        end
        if defined?(@sidekiq_transaction_guard_saved_mode)
          Sidekiq::TransactionGuard.thread_local_mode = @sidekiq_transaction_guard_saved_mode
        end
      end
    end
  end
end

# If using ActiveSupport::TestCase, automatically include the helper.
if defined?(ActiveSupport::TestCase)
  # Included with `send` so that YARD doesn't try to statically resolve the
  # ActiveSupport::TestCase namespace when generating documentation.
  ActiveSupport::TestCase.send(:include, Sidekiq::TransactionGuard::MinitestHelper)
end
