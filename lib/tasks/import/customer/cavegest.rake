namespace :import do
  namespace :customer do
    desc "Importe les clients CaveGest"
    task :cavegest do
      Customer::Import::Cavegest.new(File.join(DATA_DIR, "export_clients_cavegest.xlsx")).call
    end
  end
end
