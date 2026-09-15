require "bundler/setup"
require "active_record"
require "active_support/all"
require "bigdecimal/util"
require "csv"
require "fileutils"
require "logger"
require "roo"
require "set"

APP_ROOT = File.expand_path("..", __dir__)
DATA_DIR = File.join(APP_ROOT, "data")

DEFAULT_DATABASE_URL = "postgres://localhost:5432/baqio_migration".freeze

database_url = ENV.fetch("DATABASE_URL", DEFAULT_DATABASE_URL)
database_url = "#{database_url}_test" if ENV["APP_ENV"] == "test"

ActiveRecord::Base.establish_connection(database_url)

ActiveRecord::Base.logger = Logger.new(ENV["AR_LOG"] ? $stdout : IO::NULL)

%w[app/models lib].each do |dir|
  Dir[File.join(APP_ROOT, dir, "**", "*.rb")].sort.each { |file| require file }
end

%w[importer.rb importer/normalization.rb importer/base.rb].each do |file|
  require File.join(APP_ROOT, "app", "services", file)
end

Dir[File.join(APP_ROOT, "app", "services", "**", "*.rb")].sort.each { |file| require file }
