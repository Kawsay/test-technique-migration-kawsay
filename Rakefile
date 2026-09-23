require_relative "config/environment"

Dir[File.join(APP_ROOT, "lib", "tasks", "**", "*.rake")].sort.each { |f| load f }

namespace :db do
  desc "Crée (ou recrée) la base à partir de db/schema.rb"
  task :setup do
    puts Importer::Console.title("Création de la base")

    ActiveRecord::Migration.verbose = false
    config = ActiveRecord::Base.connection_db_config
    name   = config.database

    ActiveRecord::Base.establish_connection(config.configuration_hash.merge(database: "postgres"))
    ActiveRecord::Base.connection.drop_database(name)
    ActiveRecord::Base.connection.create_database(name)
    ActiveRecord::Base.establish_connection(config)

    load File.join(APP_ROOT, "db", "schema.rb")
    puts "Base #{name} prête."
  end
end

namespace :import do
  desc "Rejoue la reprise complète (tarifs, tiers, contrôles)"
  task all: ["import:product_price:cavegest", "import:customer:cavegest", "import:report"]
end

task default: :spec

desc "Lance la suite de tests"
task :spec do
  sh "bundle exec rspec"
end
