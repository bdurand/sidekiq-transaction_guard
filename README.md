# Sidekiq Transaction Guard

[![Continuous Integration](https://github.com/bdurand/sidekiq-transaction_guard/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/sidekiq-transaction_guard/actions/workflows/continuous_integration.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)
[![Gem Version](https://badge.fury.io/rb/sidekiq-transaction_guard.svg)](https://badge.fury.io/rb/sidekiq-transaction_guard)

You should never call a Sidekiq worker that relies on the state of the database from within a database transaction. You will end up with a race condition since the worker could kick off before the transaction is actually written to the database. This gem can be used to highlight where your code may be scheduling workers in an indeterminate state.

## The Problem

Consider this case:

```ruby
class Post < ActiveRecord::Base
  # BAD: DO NOT DO THIS
  after_create do
    PostCreatedWorker.perform_async(id)
  end
end

class PostCreatedWorker
  include Sidekiq::Worker

  def perform(post_id)
    post = Post.find_by(id: post_id)
    if post
      do_something_with(post)
    end
  end
end
```

In this case, the `PostCreatedWorker` job will be created for a new `Post` record in Sidekiq before the data is actually written to the database. If Sidekiq picks up that worker and tries to execute it before the transaction is committed, `Post.find_by(id: post_id)` won't find anything and the worker will exit without performing its task. Even if the worker doesn't need to read from the database, there is still a chance for an error to rollback the transaction leaving a possibility of workers running that should not have been scheduled.

To solve this, workers like this should be invoked in ActiveRecord from an `after_commit` callback. These callbacks are guaranteed to only execute after the data has been written to the database. However, as your application grows and gets more complicated, it can be difficult to ensure that workers are not being scheduled in the middle of transactions.

Switching from callbacks to service objects won't help you either, because service objects can be wrapped in transactions as well. They will just give you a new problem to solve.

```ruby
class CreatePost
  def initialize(attributes)
    @attributes = attributes
  end

  def call
    post = Post.create!(@attributes)
    PostCreatedWorker.perform_async(post.id)
  end
end

# Still calling `perform_async` inside a transaction.
Post.transaction do
  CreatePost.new(post_1_attributes).call
  CreatePost.new(post_2_attributes).call
end
```

## The Solution

You can use this gem to add Sidekiq client middleware that will either warn you or raise an error when workers are scheduled inside of a database transaction.

### Rails Applications

If you're using Rails, the middleware is automatically added via a Railtie. The default mode will be `:error` in development and test environments, and `:warn` in production. You don't need any additional configuration, though you can customize the mode as described below.

### Non-Rails Applications

For non-Rails applications, you need to manually add the middleware in your application's initialization code:

```ruby
require 'sidekiq/transaction_guard'

Sidekiq::TransactionGuard::Middleware.init
```

### Mode

You can set the mode at any time. The mode can be one of `[:warn, :stderr, :error, :disabled]`.

```ruby
# Raise errors
Sidekiq::TransactionGuard.mode = :error

# Log to STDERR
Sidekiq::TransactionGuard.mode = :stderr

# Log to Sidekiq.logger
Sidekiq::TransactionGuard.mode = :warn

# Disable entirely
Sidekiq::TransactionGuard.mode = :disabled
```

You can set the mode when initializing the middleware:

```ruby
Sidekiq::TransactionGuard::Middleware.init(mode: :error)
```

You can also set the mode on individual worker classes with `sidekiq_options transaction_guard: mode`. The worker-specific mode will override the global mode.

```ruby
class SomeWorker
  include Sidekiq::Worker

  sidekiq_options transaction_guard: :error
end
```

You can use the `:disabled` mode to allow individual worker classes to be scheduled inside of transactions where the worker logic doesn't care about the state of the database. For instance, if you use a Sidekiq worker to report errors, you would want to allow it inside of transactions. If you don't control the worker you want to change the mode on, you can simply call this in an initializer:

```ruby
SomeWorker.sidekiq_options.merge(transaction_guard: :disabled)
```

#### Default Modes

**Rails applications**: The default mode is `:error` in development and test environments, and `:warn` in production or other environments.

**Non-Rails applications**: The default mode is `:stderr` if `ENV["RAILS_ENV"]` or `ENV["RACK_ENV"]` is set to `"test"`, otherwise `:warn`.

### Notification Handlers

You can also set a block to be called if a worker is scheduled inside of a transaction. This can be useful if you use an error logging service to notify you of problematic calls in production so you can fix them. Note that notification handlers are only called when the mode is `:warn` or `:stderr` (not when mode is `:error` or `:disabled`).

```ruby
# Define a global notify handler
Sidekiq::TransactionGuard.notify do |job|
  # Do whatever you need to. The job argument will be a Sidekiq job hash.
end

# Define on a per worker level
class SomeWorker
  include Sidekiq::Worker

  sidekiq_options notify_in_transaction: -> (job) { # Do something }
end

# Disable the global notification handler on a worker
class SomeOtherWorker
  include Sidekiq::Worker

  sidekiq_options notify_in_transaction: false
end
```

## Multiple Databases

Out of the box, this gem only deals with one database and monitors the connection pool returned by `ActiveRecord::Base.connection`. If you have multiple databases (or even multiple connections to the same database) that you want to track, you need to tell `Sidekiq::TransactionGuard` about them.

```ruby
class MyClass < ActiveRecord::Base
  # This establishes a new connection pool.
  establish_connection(configurations["otherdb"])
end

Sidekiq::TransactionGuard.add_connection_class(MyClass)
```

The class is used to get to the connection pool used for the class. You only need to add one class per connection pool, so you don't need to add any subclasses of `MyClass`.

## Transactional Fixtures In Tests

If you're using transaction fixtures in your tests, there will always be a database transaction open.

### Rails Transactional Fixtures

When using Rails transactional fixtures, you'll need to wrap each test in a `Sidekiq::TransactionGuard.testing` block and set the number of transaction levels to ignore.

### RSpec Support

If you're using RSpec, you can use the built-in RSpec helper to automatically set up the hooks to deal with transactional fixtures. Add this line to your `spec_helper.rb` or `rails_helper.rb` file:

```ruby
require 'sidekiq/transaction_guard/rspec'
```

This will also add support for adding a metadata tag to your specs to control the transaction guard mode on a per-spec basis. For example:

```ruby
RSpec.describe "Some feature", sidekiq_transaction_guard: :disabled do
  it "does something that schedules workers inside transactions" do
    # ...
  end
end
```

### DatabaseCleaner Support

If you're using [DatabaseCleaner](https://github.com/DatabaseCleaner/database_cleaner) in your tests, you just need to include this snippet in your test suite initializer:

```ruby
require 'sidekiq/transaction_guard/database_cleaner'
```

This will add the appropriate code so that the surrounding transaction in the test suite is ignored (i.e. workers will only warn/error if there is more than one open transaction).

### Minitest Support

If you're using Minitest with `ActiveSupport::TestCase` (Rails default), you can use the built-in Minitest helper to automatically set up the hooks for transactional fixtures. Add this line to your `test_helper.rb` file:

```ruby
require 'sidekiq/transaction_guard/minitest'
```

This will automatically wrap each test in the appropriate `testing` block and handle transactional fixtures.

If you're using plain Minitest (without `ActiveSupport::TestCase`), you can manually include the helper module:

```ruby
class MyTests < Minitest::Test
  include Sidekiq::TransactionGuard::MinitestHelper

  def test_something
    # Test code here
  end
end
```

Alternatively, you can manually use the `testing` method with minitest-hooks:

```ruby
class MyTests < Minitest::Test
  # Using minitest-hooks gem
  def around(&block)
    Sidekiq::TransactionGuard.testing(base_transaction_level: 1) do
      block.call
    end
  end
end
```

### Disabling When Setting Up Test Data

If you have test setup code that is triggering the transaction guard with false positives, you can temporarily disable the transaction guard within a block:

```ruby
Sidekiq::TransactionGuard.disable do
  # Code that schedules workers inside transactions, such as test setup code.
end
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem "sidekiq-transaction_guard"
```

And then execute:
```bash
$ bundle install
```

Or install it yourself as:
```bash
$ gem install sidekiq-transaction_guard
```

## Contributing

Open a pull request on GitHub.

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
