namespace :import do
  namespace :product_price do
    desc "Importe les produits et grilles tarifaires CaveGest"
    task :cavegest do
      puts Importer::Console.title("Import des produits et tarifs CaveGest")

      report   = MigrationReport.new
      layout   = Importer::Cavegest::ProductPricesLayout
      adapter  = Importer::Adapter::Csv.new(File.join(DATA_DIR, "export_tarifs_cavegest.csv"),
                                           fallback_encoding: layout::FALLBACK_ENCODING, col_sep: layout::COL_SEP)
      accepted = Importer::ProductPrices::Prepare.new(adapter: adapter, layout_class: layout, report: report).call

      Importer::ProductPrices::Upsert.new(accepted: accepted, source: adapter.file_name, report: report).call

      puts Importer::Summary.new(report).to_s
      path = Importer::IssuesCsv.new(report).write(Importer::IssuesCsv.path_for(adapter.file_name))
      puts "", "Anomalies détaillées : #{Importer::Console.paint(path, :bold)}"
    end
  end
end
