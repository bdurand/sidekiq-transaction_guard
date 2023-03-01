# frozen_string_literal: true

require "bundler/setup"
require "sidekiq/transaction_guard"

require "active_record"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
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
