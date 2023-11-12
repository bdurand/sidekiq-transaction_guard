# Sidekiq::TransactionGuard

[![Build Status](https://travis-ci.com/bdurand/sidekiq-transaction_guard.svg?branch=master)](https://travis-ci.com/bdurand/sidekiq-transaction_guard)
[![Maintainability](https://api.codeclimate.com/v1/badges/17bbf5cb6eda022028fe/maintainability)](https://codeclimate.com/github/bdurand/sidekiq-transaction_guard/maintainability)

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

In this case, the `PostCreatedWorker` job will be created for a new `Post` record in Sidekiq before the data is actually written to the database. If Sidekiq picks up that worker and tries to execute it before the transaction is committed, `Post.find_by(id: post_id)` won't find anything and the worker will exit without performing it's task. Even if the worker doesn't need to read from the database, there is still a chance for an error to rollback the transaction leaving a possibility of workers running that should not have been scheduled.

To solve this, workers like this should be invoked in ActiveRecord from an `after_commit` callback. These callbacks are guaranteed to only execute after the data has been written to the database. However, as your application grows and gets more complicated, it can be difficult to ensure that workers are not being scheduled in the middle of transactions.

Switching from callbacks to service objects won't help you either, because service objects can be wrapped in transactions as well. The will just give you a new problem to solve.

```ruby
class CreatePost
  def initialize(attributes)
    @attributes = attributes
  end

  def call
    post = Post.create!(attributes)
    PostCreatedWorker.perform_async(post.id)
  end
end

# Still calling `perform_async` inside a transaction.
Post.transaction do
  CreatePost.new(post_1_attributes)
  CreatePost.new(post_2_attributes)
end
```

## The Solution

You can use this gem to add Sidekiq client middleware that will either warn you or raise an error when workers are scheduled inside of a database transaction. You can do this by simply adding this to your application's initialization code:

```ruby
require 'sidekiq/transaction_guard'

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add(Sidekiq::TransactionGuard::Middleware)
  end
end
```

### Mode

By default, the behavior is to log that a worker is being scheduled inside of a transaction to the `Sidekiq.logger`. If you are running a test suite, you may want to expose the problematic calls by either raising errors or logging the calls to standard error. The mode can be one of `[:warn, :stderr, :error, :disabled]`.

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

You can also set the mode on individual worker classes with `sidekiq_options transaction_guard: mode`.

```ruby
class SomeWorker
  include Sidekiq::Worker

  sidekiq_options transaction_guard: :error
end
```


You can use the `:disabled` mode to allow individual worker classes to be scheduled inside of transactions where the worker logic doesn't care about the state of the database. For instance, if you use a Sidekiq worker to report errors, you would want to all it inside of transactions. If you don't control the worker you want to change the mode on, you simply call this in an initializer:

```ruby
SomeWorker.sidekiq_options.merge(transaction_guard: :disabled)
```

You could

### Notification Handlers

You can also set a block to be called if a worker is scheduled inside of a transaction. This can be useful if you use an error logging service to notify you of problematic calls in production so you can fix them.

```ruby
# Define a global notify handler
Sidekiq::TransactionGuard.notify do |job|
  # Do what ever you need to. The job argument will be a Sidekiq job hash.
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
  # This estabilishes a new connection pool.
  establish_connection(configurations["otherdb"])
end

Sidekiq::TransactionGuard.add_connection_class(MyClass)
```

The class is used to get to the connection pool used for the class. You only need to add one class per connection pool, so you don't need to add any subclasses of `MyClass`.

## Transaction Fixtures In Tests

If you're using transaction fixtures in your tests, there will always be a database transaction open. If you're using [DatabaseCleaner](https://github.com/DatabaseCleaner/database_cleaner) in your tests, you just need to include this snippet in your test suite initializer:

```ruby
require 'sidekiq/transaction_guard/database_cleaner'
```

This will add the appropriate code so that the surrounding transaction in the test suite is ignored (i.e. workers will only warn/error if there is more than one open transaction).

If you're using something else for your transactional fixtures or have some other weird setup, look in the `lib/sidekiq_transaction_guard/database_cleaner.rb` file for an example of what you need to do.
