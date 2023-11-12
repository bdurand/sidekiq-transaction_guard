# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "sidekiq-transaction_guard"
  spec.version = File.read(File.expand_path("VERSION", __dir__)).strip
  spec.authors = ["Brian Durand", "Winston Durand"]
  spec.email = ["bbdurand@gmail.com", "me@winstondurand.com"]

  spec.summary = "Protect from accidentally invoking Sidekiq jobs when there are open database transactions"
  spec.homepage = "https://github.com/bdurand/sidekiq-transaction_guard"
  spec.license = "MIT"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  ignore_files = %w[
    .
    Appraisals
    Gemfile
    Gemfile.lock
    Rakefile
    bin/
    gemfiles/
    spec/
  ]
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject { |f| ignore_files.any? { |path| f.start_with?(path) } }
  end

  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.5"

  spec.add_dependency "activerecord", ">= 5.0"
  spec.add_dependency "sidekiq", ">= 4.0"

  spec.add_development_dependency "bundler"
end
