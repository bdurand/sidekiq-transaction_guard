# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.3

### Fixed

- Transactions opened by the connection pool pinning machinery used by transactional tests in Rails 7.2+ are no longer counted as application transactions. Rails 7.2 pins a single connection wrapped in a non-joinable transaction and shares it with every thread, but the transaction level baseline captured by the test integrations is stored per thread. Threads other than the test runner thread (e.g. Capybara server threads, ActionCable workers, or inline Sidekiq jobs in system tests) had no baseline, so every job they enqueued was falsely flagged as inside a transaction. The allowed transaction level is now derived from the pool's pinned connection state as well, which is visible from all threads. Transactions opened by application code, including non-joinable ones, are still counted. The pinned connection state is only consulted once a test integration has started a testing context, so pinning a connection outside of tests does not bypass the guard.

## 1.1.2

### Fixed

- `Sidekiq::TransactionGuard.init` now registers the client middleware in the Sidekiq server process as well. Previously jobs enqueued from within other jobs bypassed the transaction guard entirely because `Sidekiq.configure_client` is a no-op in server processes.
- Fixed the Minitest helper so the transaction tracking set up by `Sidekiq::TransactionGuard.testing` remains active for the duration of the test. Previously the testing context was torn down when `setup` returned, so the transaction level snapshot was discarded before the test body ran and tests using transactional fixtures would raise false positive errors on every enqueue. The helper now uses Minitest's `before_setup`/`after_teardown` lifecycle hooks and takes the snapshot after all other setup hooks (including transactional fixtures) have run.
- The Minitest helper no longer permanently changes the global mode when it is included and no longer defines `setup`/`teardown` methods that could be silently overridden by test classes defining their own.
- `Sidekiq::TransactionGuard.disable` and the RSpec/Minitest test integrations now use a thread local mode override instead of mutating the global mode. This fixes race conditions where disabling the guard in one thread would disable it for all threads, and where concurrent save/restore of the global mode could leave it in the wrong state.
- The RSpec integration now registers its per-example hooks at the example group level so the transaction level snapshot is taken after rspec-rails opens the transactional fixture transaction instead of before it.
- Worker-level `transaction_guard` sidekiq options are now honored when the value is a string as well as a symbol.
- Connection errors from registered connection classes without an established connection no longer raise from `in_transaction?`.
- Use `lease_connection` instead of the deprecated `connection` method on ActiveRecord 7.2+.

### Added

- `Sidekiq::TransactionGuard.thread_local_mode` and `thread_local_mode=` to override the mode for the current thread only.
- `Sidekiq::TransactionGuard.default_mode` to read the globally configured mode, ignoring any thread local override.

## 1.1.1

### Changed

- Refactored the RSpec helper to set the transaction guard mode to :disabled during setup and teardown, and only set it to the desired mode during the example execution. This ensures that setup and teardown transactions are ignored by the transaction guard, while still allowing tests to specify their desired mode for the duration of the example.
- Disable transaction guard when running tests in inline mode since since inline mode is not compatible with the transaction guard and will cause all tests to fail.

## 1.1.0

### Added

- `Sidekiq::TransactionGuard.testing` now automatically sets the allowed transaction level when the block begins. This provides better support transactional fixtures in test environments.
- Added `Sidekiq::TransactionGuard.disable` method to allow temporarily disabling the transaction guard within a block. This is useful in test environments when you want to setup data for your tests without worrying about transaction levels.
- Added `count` parameter to `set_allowed_transaction_level` to allow setting the allowed transaction level explicitly. This is useful for test setups where the transaction level cannot be determined automatically, such as when using ActiveRecord transactional fixtures.
- Added Railtie for automatic integration with Rails applications.
- Added helpers for easier testing setup with RSpec.
- Added `Sidekiq::TransactionGuard::Middleware.init` method to simplify middleware initialization.
- Added minitest helper module for easier integration with Minitest test suites.

### Removed

- Removed support for ActiveRecord versions prior to 6.0.
- Removed support for Sidekiq versions prior to 6.0.

## 1.0.3

### Changed

- Updated Middleware to include Sidekiq::ClientMiddleware for Sidekiq 7.0 compatibility


## 1.0.2

### Changed

- Updated database cleaner dependency to use database_cleaner-active_record instead of deprecated database_cleaner gem.
- Added YARD doc param and return types.

## 1.0.1

### Added

- Sidekiq 6.0 compatibility

## 1.0.0

### Added

- Initial release
