require "spec_helper"

RSpec.describe Importer::ProductPrices::Upsert do
  let(:report) { MigrationReport.new }
  let(:source) { "tarifs.csv" }

  # Un produit préparé par Importer::ProductPrices::Prepare, prêt à être écrit.
  # prices : { code de la grille => montant HT }.
  def accepted(line, prices: { "DEPC" => "10.00" }, empty_grids: [], **product)
    defaults = { reference: "REF1", name: "Vin rouge", vat_rate: BigDecimal("20") }
    record   = Importer::Layout::Base::Record.new(line: line, cells: { reference: product.fetch(:reference, "REF1") })
    amounts  = prices.map { |grid_code, amount| { grid_code: grid_code, amount_ht: BigDecimal(amount) } }

    Importer::ProductPrices::Prepare::Accepted.new(record: record, product: defaults.merge(product), prices: amounts,
                                                   empty_grids: empty_grids)
  end

  def upsert(accepted_products, report: self.report)
    described_class.new(accepted: accepted_products, source: source, report: report).call
  end

  def bilan(entity, report: self.report) = report.bilans[[source, entity]]

  def prices_in_database
    ProductPrice.joins(:product).pluck("products.reference", :grid_code, :amount_ht)
  end

  def issues(code)
    report.issues.select { |candidate| candidate.code == code }
  end

  it "creates the products with their prices" do
    upsert([accepted(2, reference: "REF1", prices: { "DEPC" => "10.00", "CHR" => "9.00" }),
            accepted(3, reference: "REF2", name: "Vin blanc", prices: { "DEPC" => "12.00" })])

    expect(Product.pluck(:reference, :name)).to contain_exactly(["REF1", "Vin rouge"], ["REF2", "Vin blanc"])
    expect(prices_in_database).to contain_exactly(["REF1", "DEPC", BigDecimal("10")], ["REF1", "CHR", BigDecimal("9")],
                                                  ["REF2", "DEPC", BigDecimal("12")])
  end

  it "reports how many products and prices were created" do
    upsert([accepted(2, prices: { "DEPC" => "10.00", "CHR" => "9.00" })])

    expect(bilan(:products)).to have_attributes(accepted: 1, created: 1, updated: 0, unchanged: 0)
    expect(bilan(:product_prices)).to have_attributes(accepted: 2, created: 2, updated: 0, unchanged: 0)
  end

  describe "replaying the same file" do
    it "writes nothing the second time" do
      products = [accepted(2, prices: { "DEPC" => "10.00", "CHR" => "9.00" })]
      upsert(products)
      written_at = Product.pluck(:updated_at) + ProductPrice.pluck(:updated_at)

      second_report = MigrationReport.new
      upsert(products, report: second_report)

      expect(Product.pluck(:updated_at) + ProductPrice.pluck(:updated_at)).to eq(written_at)
      expect(bilan(:products, report: second_report)).to have_attributes(created: 0, updated: 0, unchanged: 1)
      expect(bilan(:product_prices, report: second_report)).to have_attributes(created: 0, updated: 0, unchanged: 2)
    end

    it "updates a price that changed" do
      upsert([accepted(2, prices: { "DEPC" => "10.00" })])

      second_report = MigrationReport.new
      upsert([accepted(2, prices: { "DEPC" => "11.00" })], report: second_report)

      expect(prices_in_database).to eq([["REF1", "DEPC", BigDecimal("11")]])
      expect(bilan(:product_prices, report: second_report)).to have_attributes(created: 0, updated: 1, unchanged: 0)
    end

    it "removes a price whose grid is now empty" do
      upsert([accepted(2, prices: { "DEPC" => "10.00", "SALON" => "14.00" })])
      upsert([accepted(2, prices: { "DEPC" => "10.00" }, empty_grids: ["SALON"])], report: MigrationReport.new)

      expect(prices_in_database).to eq([["REF1", "DEPC", BigDecimal("10")]])
    end

    it "reports the removed price with its former amount" do
      upsert([accepted(2, prices: { "DEPC" => "10.00", "SALON" => "14.00" })], report: MigrationReport.new)
      upsert([accepted(2, prices: { "DEPC" => "10.00" }, empty_grids: ["SALON"])])

      expect(issues(:price_removed).first)
        .to have_attributes(level: :info, line: 2, entity: "Produit REF1, grille SALON", value: BigDecimal("14"))
    end

    # La lecture a échoué : rien ne dit que le client a supprimé ce tarif.
    it "keeps a price whose grid is unreadable" do
      upsert([accepted(2, prices: { "DEPC" => "10.00", "SALON" => "14.00" })])
      upsert([accepted(2, prices: { "DEPC" => "10.00" })], report: MigrationReport.new)

      expect(prices_in_database).to contain_exactly(["REF1", "DEPC", BigDecimal("10")], ["REF1", "SALON", BigDecimal("14")])
    end

    it "does not touch the products missing from the file" do
      upsert([accepted(2, reference: "REF1"), accepted(3, reference: "REF2")])
      upsert([accepted(2, reference: "REF1", empty_grids: ["SALON"])], report: MigrationReport.new)

      expect(prices_in_database).to include(["REF2", "DEPC", BigDecimal("10")])
    end
  end

  describe "duplicated references" do
    it "imports no version of a reference read twice, and reports every row" do
      upsert([accepted(2, reference: "REF1"), accepted(3, reference: "REF1"), accepted(4, reference: "REF2")])

      expect(Product.pluck(:reference)).to eq(["REF2"])
      expect(issues(:duplicate_identical).map { |candidate| [candidate.level, candidate.line, candidate.value] })
        .to eq([[:rejected, 2, "2, 3"], [:rejected, 3, "2, 3"]])
    end

    # Les corrections signalées sur une ligne non reprise n'appellent aucune action du client.
    it "drops the other anomalies of the rejected rows" do
      report.add(level: :repaired, code: :price_ttc_converted, source: source, line: 2, entity: "Produit REF1")
      upsert([accepted(2, prices: { "DEPC" => "10.00" }), accepted(3, prices: { "DEPC" => "12.00" })])

      expect(report.issues_for_client.map { |candidate| candidate.code }).to eq([:duplicate_conflict, :duplicate_conflict])
      expect(report.issues.map { |candidate| candidate.code }).to include(:price_ttc_converted)
    end

    it "distinguishes rows whose prices differ" do
      upsert([accepted(2, prices: { "DEPC" => "10.00" }), accepted(3, prices: { "DEPC" => "12.00" })])

      expect(Product.count).to eq(0)
      expect(issues(:duplicate_conflict).map { |candidate| candidate.line }).to eq([2, 3])
    end
  end

  it "writes nothing when there is no product to import" do
    upsert([])

    expect(Product.count).to eq(0)
    expect(bilan(:products)).to have_attributes(accepted: 0, created: 0, updated: 0, unchanged: 0)
    expect(bilan(:product_prices)).to have_attributes(accepted: 0, created: 0, updated: 0, unchanged: 0)
  end

  describe "with the client's price list export" do
    before(:all) do
      ProductPrice.delete_all
      Product.delete_all
      layout   = Importer::Cavegest::ProductPricesLayout
      adapter  = Importer::Adapter::Csv.new(data_path("export_tarifs_cavegest.csv"),
                                           fallback_encoding: layout::FALLBACK_ENCODING, col_sep: layout::COL_SEP)
      accepted = Importer::ProductPrices::Prepare.new(adapter: adapter, layout_class: layout,
                                                      report: MigrationReport.new).call

      @first_report = MigrationReport.new
      described_class.new(accepted: accepted, source: "export_tarifs_cavegest.csv", report: @first_report).call

      @second_report = MigrationReport.new
      described_class.new(accepted: accepted, source: "export_tarifs_cavegest.csv", report: @second_report).call
    end

    after(:all) do
      ProductPrice.delete_all
      Product.delete_all
    end

    # 113 lignes retenues, dont 12 portant l'une des 6 références lues deux fois.
    it "imports every product but those whose reference is read twice" do
      expect(Product.count).to eq(101)
      expect(@first_report.bilans[["export_tarifs_cavegest.csv", :products]])
        .to have_attributes(accepted: 101, created: 101, updated: 0, unchanged: 0)
    end

    # 502 tarifs lus, moins les 53 des lignes en double.
    it "imports the prices of these products" do
      expect(ProductPrice.count).to eq(449)
    end

    it "reports the rows of the duplicated references" do
      expect(@first_report.by_level(:rejected).map { |candidate| candidate.line })
        .to contain_exactly(12, 90, 18, 107, 27, 72, 32, 111, 33, 122, 86, 101)
    end

    it "writes nothing when replayed" do
      expect(@second_report.bilans[["export_tarifs_cavegest.csv", :products]])
        .to have_attributes(accepted: 101, created: 0, updated: 0, unchanged: 101)
      expect(@second_report.bilans[["export_tarifs_cavegest.csv", :product_prices]])
        .to have_attributes(created: 0, updated: 0, unchanged: 449)
    end
  end
end
