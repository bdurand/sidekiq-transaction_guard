# frozen_string_literal: true

require "sidekiq/transaction_guard"

module Sidekiq
  module TransactionGuard
    # RSpec integration. Requiring this file wraps every example in a
    # `Sidekiq::TransactionGuard.testing` block and manages the transaction guard
    # mode with a thread local override so parallel test threads can't interfere
    # with each other.
    #
    # The per example mode can be controlled with the `:sidekiq_transaction_guard`
    # metadata tag. The value can be a mode symbol, `false` to disable the guard,
    # or `:default` to use the globally configured mode. Untagged examples run
    # with the `:error` mode.
    #
    # This file should be required after rspec-rails (or any other library that
    # opens transactions in its setup hooks) so that the transaction level
    # snapshot taken before each example runs after those transactions are opened.
    #
    # @api private
    module RSpecIntegration
      def self.included(example_group)
        # Nested example groups inherit hooks from their parent group, so only
        # register the hooks on the outermost group that includes this module.
        return if example_group.is_a?(Class) && example_group.superclass.include?(RSpecIntegration)

        # These are registered as group level hooks so they run after hooks added
        # by modules included earlier — in particular after rspec-rails has opened
        # the transactional fixture transaction — so the snapshot taken here
        # treats transactions opened by test setup as the baseline.
        example_group.before do |example|
          Sidekiq::TransactionGuard::RSpecIntegration.apply_example_mode(example)
          Sidekiq::TransactionGuard.set_allowed_transaction_level(:all)
        end

        example_group.after do
          # Disable the guard before fixture rollback and other teardown hooks run.
          Sidekiq::TransactionGuard.thread_local_mode = :disabled
        end
      end

      def self.apply_example_mode(example)
        metadata = example.metadata
        if metadata.key?(:sidekiq_transaction_guard)
          mode = metadata[:sidekiq_transaction_guard]
          mode = :disabled if mode == false
          mode = nil if mode == :default
          mode = :error unless mode.nil? || mode.is_a?(Symbol)
          Sidekiq::TransactionGuard.thread_local_mode = mode
        elsif Sidekiq::TransactionGuard.thread_local_mode == :disabled
          # Apply the default mode only if an earlier hook hasn't already set one.
          Sidekiq::TransactionGuard.thread_local_mode = :error
        end
      end
    end
  end
end

RSpec.configure do |config|
  # Disable the guard for code running outside of examples, such as suite level
  # setup and teardown.
  config.before(:suite) do
    Sidekiq::TransactionGuard.thread_local_mode = :disabled
  end

  config.after(:suite) do
    Sidekiq::TransactionGuard.thread_local_mode = nil
  end

  # Wrap each example in a testing block and keep the guard disabled except
  # while the example itself is running.
  config.around do |example|
    saved_mode = Sidekiq::TransactionGuard.thread_local_mode
    begin
      Sidekiq::TransactionGuard.thread_local_mode = :disabled
      Sidekiq::TransactionGuard.testing { example.run }
    ensure
      Sidekiq::TransactionGuard.thread_local_mode = saved_mode
    end
  end

  config.include Sidekiq::TransactionGuard::RSpecIntegration
end
