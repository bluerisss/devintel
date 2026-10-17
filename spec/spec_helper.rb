# frozen_string_literal: true

require "devintel"
require "erb"
require "tmpdir"
require "fileutils"
require "pathname"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  config.example_status_persistence_file_path = ".rspec_status"
  Kernel.srand config.seed

  config.include SandboxRepository
  config.include RunningServer
  config.include GitRepository
end
