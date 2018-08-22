require "bundler/setup"
require "sidekiq-transaction-guard"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

ActiveRecord::Base.establish_connection("adapter" => "sqlite3", "database" => ":memory:")

class TestModel < ActiveRecord::Base
  connection.create_table(table_name) do |t|
    t.column :name, :string
  end unless table_exists?
end

class OtherConnectionModel < ActiveRecord::Base
  establish_connection("adapter" => "sqlite3", "database" => ":memory:")

  connection.create_table(table_name) do |t|
    t.column :name, :string
  end unless table_exists?
end

class UnregisteredConnectionModel < ActiveRecord::Base
  establish_connection("adapter" => "sqlite3", "database" => ":memory:")

  connection.create_table(table_name) do |t|
    t.column :name, :string
  end unless table_exists?
end

SidekiqTransactionGuard.add_connection_class(OtherConnectionModel)
