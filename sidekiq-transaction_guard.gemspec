# frozen_string_literal: true

require_relative "lib/sidekiq/transaction_guard/version"

Gem::Specification.new do |spec|
  spec.name          = "sidekiq-transaction_guard"
  spec.version       = Sidekiq::TransactionGuard::VERSION
  spec.authors       = ["Brian Durand", "Winston Durand"]
  spec.email         = ["bbdurand@gmail.com", "me@winstondurand.com"]

  spec.summary       = "Protect from accidentally invoking Sidekiq jobs when there are open database transactions"
  spec.homepage      = "https://github.com/bdurand/sidekiq-transaction_guard"
  spec.license       = "MIT"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  ignore_files = %w(
    .gitignore
    .travis.yml
    Appraisals
    Gemfile
    Gemfile.lock
    Rakefile
    gemfiles/
    spec/
  )
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject{ |f| ignore_files.any?{ |path| f.start_with?(path) } }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.2.2'

  spec.add_dependency "activerecord", ">= 4.0"
  spec.add_dependency "sidekiq", ">= 3.0"

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "database_cleaner", ">= 1.5"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "appraisal"
end
