# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
