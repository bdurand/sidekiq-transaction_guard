# frozen_string_literal: true
# Check each of the versions of ActiveRecord to make sure that we can actually run
# with that version

RAILS_MINOR_RELEASES = ["4.0", "4.1", "4.2", "5.0", "5.1", "5.2"].freeze

RAILS_MINOR_RELEASES.each do |version|
  appraise "activerecord-#{version}" do
    gem "activerecord", "~> #{version}.0"
  end
end
