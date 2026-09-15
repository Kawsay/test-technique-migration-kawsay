ENV["APP_ENV"] = "test"

require_relative "../config/environment"

ActiveRecord::Migration.verbose = false
load File.join(APP_ROOT, "db", "schema.rb")

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random

  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end

def data_path(name)
  File.join(APP_ROOT, "data", name)
end
