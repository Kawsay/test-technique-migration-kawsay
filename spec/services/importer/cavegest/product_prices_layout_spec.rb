require "spec_helper"

RSpec.describe Importer::Cavegest::ProductPricesLayout do
  let(:header) { described_class::COLUMNS.map { |_position, _field, name| name } }

  # Valeurs d'une ligne de produit, par position : { champ => valeur }, les autres cellules vides.
  def product(cells)
    values = Array.new(described_class::COLUMNS.size)

    described_class::COLUMNS.each do |position, field, _name|
      values[position] = cells[field]
    end

    values
  end

  # Préambule de l'export CaveGest (un commentaire, puis une ligne vide), placé avant les lignes données.
  # Son numéro de ligne est sans importance : la disposition l'écarte sans le lire.
  def with_preamble(file_rows)
    preamble = [["CaveGest 4.2 - Export des grilles tarifaires"], []].map do |values|
      Importer::Adapter::Row.new(line: 0, values: values)
    end

    preamble + file_rows
  end

  def data_row(value) = product(reference: value)
  def layout_with(file_rows) = described_class.new(with_preamble(file_rows))

  it_behaves_like "a layout"

  it "names the cells of each product, one price per grid" do
    record = layout_with(rows([header, product(reference: "REF1", name: "Vin rouge", price_depc: "10,00", price_expo: "12,00")]))
      .records.first

    expect(record.cells).to include(reference: "REF1", name: "Vin rouge", price_depc: "10,00", price_expo: "12,00")
  end

  describe "sections" do
    let(:file_rows) do
      rows([
        header,
        product(reference: "--- ROUGES ---"),
        product(reference: "REF1"),
        product(reference: "REF2"),
        product(reference: "SOUS-TOTAL ROUGES", stock: "2"),
        product(reference: "--- BLANCS ---"),
        product(reference: "REF3"),
        product(reference: "SOUS-TOTAL BLANCS", stock: "1")
      ])
    end

    let(:layout) { layout_with(file_rows) }

    it "skips the section titles and the subtotals" do
      expect(layout.records.map { |record| record.cells[:reference] }).to eq(["REF1", "REF2", "REF3"])
    end

    it "exposes the section titles and the subtotals it skips" do
      expect(layout.skipped_rows.map { |row| row.values.first })
        .to eq(["--- ROUGES ---", "SOUS-TOTAL ROUGES", "--- BLANCS ---", "SOUS-TOTAL BLANCS"])
    end

    it "tells the section of each product" do
      sections = layout.records.map { |record| [record.cells[:reference], layout.section_for(record)] }

      expect(sections).to eq([["REF1", "ROUGES"], ["REF2", "ROUGES"], ["REF3", "BLANCS"]])
    end

    it "tells no section for a product placed before any section title" do
      layout = layout_with(rows([header, product(reference: "REF1")]))

      expect(layout.section_for(layout.records.first)).to be_nil
    end
  end

  # Un fichier dont on aurait retiré le préambule à la main ne correspond plus au format de CaveGest.
  it "rejects a file without its preamble" do
    layout = described_class.new(rows([header, product(reference: "REF1"), product(reference: "REF2"), product(reference: "REF3")]))

    expect { layout.records }.to raise_error(Importer::FileRejected, /unexpected header \(column 1: expected "Ref", found "REF2"/)
  end

  describe "with the client's price list export" do
    before(:all) do
      file_rows = Importer::Adapter::Csv.new(data_path("export_tarifs_cavegest.csv"),
                                             fallback_encoding: described_class::FALLBACK_ENCODING,
                                             col_sep: described_class::COL_SEP).rows
      @layout  = described_class.new(file_rows)
      @records = @layout.records
    end

    # 129 lignes : le préambule (2), l'en-tête, 6 sections de produits, chacune avec son titre et son sous-total,
    # et une ligne vide.
    it "reads every product" do
      expect(@records.size).to eq(113)
      expect(@records.first).to have_attributes(line: 5, cells: include(reference: "LANM3"))
      expect(@records.last).to have_attributes(line: 128, cells: include(reference: "VIE212"))
    end

    it "keeps the values as written in the file" do
      product = @records.find { |record| record.cells[:reference] == "COT196" }

      expect(product.cells).to eq(
        reference:   "COT196",
        name:        "Coteaux Nord 2019",
        container:   "Bouteille - 75.0",
        color:       "Rouge",
        vat_rate:    "20",
        price_depc:  "  19,31 EUR",
        price_chr:   "16,99",
        price_expo:  "23,17",
        price_part:  "22,79",
        price_salon: nil,
        stock:       "28"
      )
    end

    it "tells the section of each product" do
      sections = @records.map { |record| @layout.section_for(record) }.tally

      expect(sections).to eq(
        "AOP ROUGES" => 14, "AOP BLANCS" => 16, "IGP" => 18, "VIN DE FRANCE" => 22, "EFFERVESCENTS" => 21, "DIVERS" => 22
      )
    end

    it "exposes the 6 section titles and the 6 subtotals" do
      expect(@layout.skipped_rows.size).to eq(12)
    end

    it "has no column beyond the expected ones" do
      expect(@layout.ignored_columns).to be_empty
    end
  end
end
