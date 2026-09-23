namespace :import do
  desc "Contrôles de cohérence sur la base après reprise"
  task :report do
    puts Importer::Console.title("Contrôles de cohérence après reprise")
    puts Importer::Audit.new(equal_price_grids: Importer::Cavegest::ProductPricesLayout::EQUAL_PRICE_GRIDS)
  end
end
