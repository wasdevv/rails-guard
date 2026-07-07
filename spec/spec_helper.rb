require "tmpdir"
require "fileutils"
require_relative "../lib/rails_guard"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

def make_rails_app(config_yaml = nil)
  dir = Dir.mktmpdir("rails-guard-app")
  FileUtils.mkdir_p(File.join(dir, "bin"))
  File.write(File.join(dir, "bin/rails"), "#!/usr/bin/env ruby\n")
  File.write(File.join(dir, ".rails-guard.yml"), config_yaml) if config_yaml
  dir
end

RAILS_APP = make_rails_app
at_exit { FileUtils.remove_entry(RAILS_APP) if File.directory?(RAILS_APP) }
