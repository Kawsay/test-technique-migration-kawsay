namespace :import do
  namespace :customer do
    desc "Importe les clients CaveGest"
    task :cavegest do
      report   = MigrationReport.new
      layout   = Importer::Cavegest::CustomersLayout
      adapter  = Importer::Adapter::Xlsx.new(File.join(DATA_DIR, "export_clients_cavegest.xlsx"), sheet: layout::SHEET)
      accepted = Importer::Customers::Prepare.new(adapter: adapter, layout_class: layout, report: report).call

      Importer::Customers::Upsert.new(accepted: accepted, source: adapter.file_name, report: report).call

      puts Importer::Summary.new(report).to_s
      puts "", "Anomalies détaillées : #{Importer::IssuesCsv.new(report).write(Importer::IssuesCsv.path_for(adapter.file_name))}"
    end
  end
end
