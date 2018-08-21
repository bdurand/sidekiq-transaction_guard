require 'rspec'

if ENV['ACTIVE_RECORD_VERSION']
  gem 'activesupport', ENV['ACTIVE_RECORD_VERSION']
  gem 'activerecord', ENV['ACTIVE_RECORD_VERSION']
end

if ENV['SIDEKIQ_VERSION']
  gem ENV['SIDEKIQ_VERSION']
end

require 'active_record'

require_relative '../lib/sidekiq_transaction_guard'

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
