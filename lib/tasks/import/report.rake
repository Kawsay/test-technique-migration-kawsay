namespace :import do
  desc "Contrôles de cohérence sur la base après reprise"
  task :report do
    puts Importer::Audit.new
  end
end
