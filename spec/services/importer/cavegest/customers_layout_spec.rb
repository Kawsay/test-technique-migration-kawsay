require "spec_helper"

RSpec.describe Importer::Cavegest::CustomersLayout do
  let(:header) { described_class::COLUMNS.map { |_position, _field, name| name } }

  # Valeurs d'une ligne de client, par position : { champ => valeur }, les autres cellules vides.
  def customer(cells)
    values = Array.new(described_class::COLUMNS.size)

    described_class::COLUMNS.each do |position, field, _name|
      values[position] = cells[field]
    end

    values
  end

  def data_row(value) = customer(reference: value)
  def layout_with(rows) = described_class.new(rows)

  it_behaves_like "a layout"

  # « Nom », « Code postal »… apparaissent deux fois dans l'en-tête : facturation, puis livraison.
  it "tells billing and shipping columns apart, although their headers are identical" do
    customer_row = customer(last_name: "Dupont", zip: 1000, shipping_last_name: "Martin", shipping_zip: 2000)
    record       = layout_with(rows([header, customer_row])).records.first

    expect(record.cells).to include(last_name: "Dupont", zip: 1000, shipping_last_name: "Martin", shipping_zip: 2000)
  end

  it "skips the TOTAL row" do
    records = layout_with(rows([header, customer(reference: "C1"), customer(reference: "TOTAL", company_name: "1 tiers")])).records

    expect(records.map { |record| record.cells[:reference] }).to eq(["C1"])
  end

  describe "with the client's customers export" do
    before(:all) do
      file_rows        = Importer::Adapter::Xlsx.new(data_path("export_clients_cavegest.xlsx"), sheet: "Feuil1").rows
      layout           = described_class.new(file_rows)
      @records         = layout.records
      @ignored_columns = layout.ignored_columns
    end

    # 5 003 lignes : l'en-tête, 4 997 clients, 4 lignes vides et la ligne TOTAL.
    it "reads every customer row" do
      expect(@records.size).to eq(4997)
      expect(@records.first).to have_attributes(line: 2, cells: include(reference: "T00001"))
      expect(@records.last).to have_attributes(line: 5001, cells: include(reference: "T05000"))
    end

    it "reads the billing and shipping postal codes from their own columns" do
      record = @records.find { |candidate| candidate.cells[:reference] == "T00013" }

      expect(record.cells).to include(zip: 4000, shipping_zip: 11100)
    end

    it "has no column beyond the expected ones" do
      expect(@ignored_columns).to be_empty
    end
  end
end
