require "spec_helper"

# Un code sans libellé s'afficherait tel quel dans le rapport du client (« zip_padded »).
# La reprise réelle des deux fichiers émet tous les codes de nos règles : elle sert de recensement.
RSpec.describe "les libellés des anomalies" do
  before(:all) do
    ProductPrice.delete_all
    Product.delete_all
    Customer.delete_all

    @report = MigrationReport.new
    import_customers(@report)
    import_product_prices(@report)
  end

  after(:all) do
    ProductPrice.delete_all
    Product.delete_all
    Customer.delete_all
  end

  def import_customers(report)
    layout   = Importer::Cavegest::CustomersLayout
    adapter  = Importer::Adapter::Xlsx.new(data_path("export_clients_cavegest.xlsx"), sheet: layout::SHEET)
    accepted = Importer::Customers::Prepare.new(adapter: adapter, layout_class: layout, report: report).call

    Importer::Customers::Upsert.new(accepted: accepted, source: adapter.file_name, report: report).call
  end

  def import_product_prices(report)
    layout   = Importer::Cavegest::ProductPricesLayout
    adapter  = Importer::Adapter::Csv.new(data_path("export_tarifs_cavegest.csv"),
                                          fallback_encoding: layout::FALLBACK_ENCODING, col_sep: layout::COL_SEP)
    accepted = Importer::ProductPrices::Prepare.new(adapter: adapter, layout_class: layout, report: report).call

    Importer::ProductPrices::Upsert.new(accepted: accepted, source: adapter.file_name, report: report).call
  end

  it "covers every code the client's files produce" do
    expect(@report.codes_without_label).to be_empty
  end

  it "covers every code the readers can emit" do
    codes = [Importer::Customers::Reader, Importer::ProductPrices::Reader].flat_map do |reader|
      reader::LEVELS_BY_CODE.keys
    end

    expect(codes - MigrationReport::LABELS.keys).to be_empty
  end

  it "labels every level" do
    expect(MigrationReport::LEVELS - MigrationReport::LEVEL_LABELS.keys).to be_empty
  end
end
