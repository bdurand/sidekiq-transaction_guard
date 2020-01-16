# frozen_string_literal: true

# The code is a little more tightly integrated with ActiveRecord so check
# all minor releases. Only need to sanity check major releases of Sidekiq.

RAILS_MINOR_RELEASES = ["6.0", "5.2", "5.1", "5.0", "4.2", "4.1", "4.0"].freeze
SIDEKIQ_MAJOR_RELEASES = ["6", "5", "4", "3"].freeze

RAILS_MINOR_RELEASES.each do |version|
  appraise "activerecord-#{version}" do
    gem "activerecord", "~> #{version}.0"
    if version.to_f < 5.2
      gem "sqlite3", "~> 1.3.0"
    end
  end
end

SIDEKIQ_MAJOR_RELEASES.each do |version|
  appraise "sidekiq-#{version}" do
    gem "sidekiq", "~> #{version}.0"
  end
end
