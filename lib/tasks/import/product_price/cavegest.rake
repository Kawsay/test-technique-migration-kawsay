namespace :import do
  namespace :product_price do
    desc "Importe les produits et grilles tarifaires CaveGest"
    task :cavegest do
      ProductPrice::Import::Cavegest.new(File.join(DATA_DIR, "export_tarifs_cavegest.csv")).call
    end
  end
end
