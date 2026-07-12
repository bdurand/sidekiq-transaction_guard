# frozen_string_literal: true

require "spec_helper"
require "minitest"
require "minitest/spec"
require "sidekiq/transaction_guard/minitest"

RSpec.describe "minitest integration" do
  it "captures the current transaction level as the base", sidekiq_transaction_guard: :default do
    original_mode = Sidekiq::TransactionGuard.mode

    saved_mode = Sidekiq::TransactionGuard.mode
    Sidekiq::TransactionGuard.mode = :error

    # Simulate transactional fixture already being open
    ActiveRecord::Base.transaction do
      Sidekiq::TransactionGuard.testing do
        expect(Sidekiq::TransactionGuard.mode).to eq :error

        # The fixture transaction is captured as the base, so should not detect it
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq false

        # But a transaction on a different registered connection should be detected
        OtherConnectionModel.transaction do
          expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
        end
      end
    end

    Sidekiq::TransactionGuard.mode = saved_mode
    expect(Sidekiq::TransactionGuard.mode).to eq original_mode
  end

  it "works without transactional fixtures", sidekiq_transaction_guard: :default do
    original_mode = Sidekiq::TransactionGuard.mode

    saved_mode = Sidekiq::TransactionGuard.mode
    Sidekiq::TransactionGuard.mode = :error

    Sidekiq::TransactionGuard.testing do
      expect(Sidekiq::TransactionGuard.mode).to eq :error

      # Should detect transaction when no fixture transaction is open
      ActiveRecord::Base.transaction do
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
      end
    end

    Sidekiq::TransactionGuard.mode = saved_mode
    expect(Sidekiq::TransactionGuard.mode).to eq original_mode
  end

  describe Sidekiq::TransactionGuard::MinitestHelper do
    # Simulates transactional fixtures by opening a transaction in before_setup
    # and rolling it back in after_teardown, like ActiveRecord::TestFixtures.
    let(:fixture_test_class) do
      Class.new(Minitest::Test) do
        def before_setup
          ActiveRecord::Base.connection.begin_transaction(joinable: false)
          @fixture_transaction_open = true
          super
        end

        def after_teardown
          super
        ensure
          if @fixture_transaction_open
            @fixture_transaction_open = false
            ActiveRecord::Base.connection.rollback_transaction
          end
        end

        def test_dummy
        end
      end
    end

    let(:test_class) do
      Class.new(fixture_test_class) do
        include Sidekiq::TransactionGuard::MinitestHelper
      end
    end

    it "keeps the transaction snapshot active during the test body" do
      test = test_class.new(:test_dummy)
      outer_mode = Sidekiq::TransactionGuard.mode

      test.before_setup
      test.setup

      begin
        # Between setup and teardown is where the test body runs.
        expect(Sidekiq::TransactionGuard.mode).to eq :error
        expect(ActiveRecord::Base.connection.open_transactions).to eq 1

        # The fixture transaction was captured as the baseline, so it is ignored.
        expect(Sidekiq::TransactionGuard.in_transaction?).to eq false

        # A transaction opened within the test is still detected.
        ActiveRecord::Base.transaction(requires_new: true) do
          expect(Sidekiq::TransactionGuard.in_transaction?).to eq true
        end

        # The testing context is still active during the test body.
        expect { Sidekiq::TransactionGuard.set_allowed_transaction_level(ActiveRecord::Base) }.not_to raise_error
      ensure
        test.before_teardown
        expect(Sidekiq::TransactionGuard.mode).to eq :disabled
        test.teardown
        test.after_teardown
      end

      expect(Sidekiq::TransactionGuard.mode).to eq outer_mode
      expect(ActiveRecord::Base.connection.open_transactions).to eq 0
    end

    it "restores the saved mode even if teardown fails" do
      failing_class = Class.new(test_class) do
        def teardown
          super
          raise "teardown error"
        end
      end

      test = failing_class.new(:test_dummy)
      outer_mode = Sidekiq::TransactionGuard.mode

      test.before_setup
      test.setup
      test.before_teardown
      expect { test.teardown }.to raise_error("teardown error")
      test.after_teardown

      expect(Sidekiq::TransactionGuard.mode).to eq outer_mode
      expect(ActiveRecord::Base.connection.open_transactions).to eq 0
    end
  end
end
