require "active_record"
require "active_support/all"
require "bigdecimal/util"
require "bundler/setup"
require "countries"
require "csv"
require "dotenv"
require "dry/monads"
require "dry/validation"
require "fileutils"
require "logger"
require "phonelib"
require "roo"
require "set"
require "uri"

APP_ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(APP_ROOT) unless $LOAD_PATH.include?(APP_ROOT)

DATA_DIR = File.join(APP_ROOT, "data")

Dotenv.load(File.join(APP_ROOT, ".env"))

module DatabaseConfig
  DEFAULT_NAME = "baqio_migration".freeze

  def self.resolve
    test_env = ENV["APP_ENV"] == "test"

    if ENV["DATABASE_URL"].present?
      uri = URI.parse(ENV["DATABASE_URL"])
      uri.path = "#{uri.path}_test" if test_env
      uri.to_s
    else
      name = ENV.fetch("DATABASE_NAME", DEFAULT_NAME)
      {
        adapter:  "postgresql",
        database: test_env ? "#{name}_test" : name,
        host:     ENV["PG_HOST"],
        port:     ENV["PG_PORT"],
        username: ENV["PG_USER"],
        password: ENV["PG_PASSWORD"]
      }.compact
    end
  end
end

ActiveRecord::Base.establish_connection(DatabaseConfig.resolve)

ActiveRecord::Base.logger = Logger.new(ENV["AR_LOG"] ? $stdout : IO::NULL)

# Locale globale laissée en :en (messages ActiveRecord) ; le rapport traduit explicitement en :fr.
I18n.load_path += Dir[File.join(APP_ROOT, "config", "locales", "*.yml")]
I18n.available_locales = %i(en fr)

%w(app/models lib).each do |dir|
  Dir[File.join(APP_ROOT, dir, "**", "*.rb")].sort.each { |file| require file }
end

# TODO: consider Zeitwerk
%w(importer.rb importer/layout.rb importer/layout/base.rb importer/reader.rb).each do |file|
  require File.join(APP_ROOT, "app", "services", file)
end

Dir[File.join(APP_ROOT, "app", "services", "**", "*.rb")].sort.each { |file| require file }

