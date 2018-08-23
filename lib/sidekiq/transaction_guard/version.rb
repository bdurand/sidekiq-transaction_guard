# frozen_string_literal: true

module Sidekiq
  module TransactionGuard
    VERSION = File.read(File.expand_path("../../../../VERSION", __FILE__)).chomp.freeze
  end
end
