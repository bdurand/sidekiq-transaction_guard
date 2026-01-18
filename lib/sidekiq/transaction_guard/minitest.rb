# frozen_string_literal: true

require "minitest"

module Sidekiq
  module TransactionGuard
    # Minitest helper module for testing with Sidekiq::TransactionGuard.
    #
    # Include this module in your test class to automatically wrap tests in the
    # Sidekiq::TransactionGuard.testing block and handle transactional fixtures.
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
      def self.included(base)
        base.class_eval do
          # Save the original mode before the test suite runs
          @@sidekiq_transaction_guard_mode = Sidekiq::TransactionGuard.mode
          Sidekiq::TransactionGuard.mode = :disabled

          def setup
            @sidekiq_transaction_guard_saved_mode = Sidekiq::TransactionGuard.mode
            mode = :error
            transaction_level = (respond_to?(:use_transactional_tests) && use_transactional_tests) ? 1 : 0
            Sidekiq::TransactionGuard.mode = mode
            Sidekiq::TransactionGuard.testing(base_transaction_level: transaction_level) do
              @sidekiq_transaction_guard_testing_block = true
              super
            end
          end

          def teardown
            super
            Sidekiq::TransactionGuard.mode = @sidekiq_transaction_guard_saved_mode
          end
        end
      end
    end
  end
end

# If using ActiveSupport::TestCase, automatically include the helper
if defined?(ActiveSupport::TestCase)
  ActiveSupport::TestCase.class_eval do
    def setup
      @sidekiq_transaction_guard_saved_mode = Sidekiq::TransactionGuard.mode
      mode = :error
      transaction_level = (respond_to?(:use_transactional_tests) && use_transactional_tests) ? 1 : 0
      Sidekiq::TransactionGuard.mode = mode

      Sidekiq::TransactionGuard.testing(base_transaction_level: transaction_level) do
        super
      end
    end

    def teardown
      super
      Sidekiq::TransactionGuard.mode = @sidekiq_transaction_guard_saved_mode
    end
  end
end
