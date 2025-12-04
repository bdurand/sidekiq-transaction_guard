# frozen_string_literal: true

require "bundler/setup"
require "sidekiq/transaction_guard"
require "sidekiq/transaction_guard/rspec"

require "active_record"

Sidekiq.logger.level = :error

RSpec.configure do |config|
  config.warnings = true
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed
end

ActiveRecord::Base.establish_connection("adapter" => "sqlite3", "database" => ":memory:")

class TestModel < ActiveRecord::Base
  unless table_exists?
    connection.create_table(table_name) do |t|
      t.column :name, :string
    end
  end
end

class OtherConnectionModel < ActiveRecord::Base
  establish_connection("adapter" => "sqlite3", "database" => ":memory:")

  unless table_exists?
    connection.create_table(table_name) do |t|
      t.column :name, :string
    end
  end
end

class UnregisteredConnectionModel < ActiveRecord::Base
  establish_connection("adapter" => "sqlite3", "database" => ":memory:")

  unless table_exists?
    connection.create_table(table_name) do |t|
      t.column :name, :string
    end
  end
end

Sidekiq::TransactionGuard.add_connection_class(OtherConnectionModel)
