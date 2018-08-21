# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "sidekiq_"
  spec.version       = File.read(File.expand_path("../VERSION", __FILE__)).chomp
  spec.authors       = ["Brian Durand"]
  spec.email         = ["bbdurand@gmail.com"]
  spec.summary       = "Protect from accidentally invoking Sidekiq jobs when there are open database transactions"
  spec.description   = "Protect from accidentally invoking Sidekiq jobs when there are open database transactions which could result in race conditions."
  spec.homepage      = "https://github.com/bdurand/sidekiq_transaction_guard"
  spec.license       = "MIT"
  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>=2.0'

  spec.add_dependency "activerecord", ">= 4.0"
  spec.add_dependency "sidekiq", ">= 3.0"

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", ">= 3.0"
  spec.add_development_dependency "database_cleaner"
  spec.add_development_dependency "sqlite3"
end
