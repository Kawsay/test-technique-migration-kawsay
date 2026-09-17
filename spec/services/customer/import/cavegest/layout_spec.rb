require "spec_helper"

RSpec.describe Customer::Import::Cavegest::Layout do
  let(:header) { described_class::COLUMNS.map { |_position, _field, name| name } }

  # Valeurs d'une ligne de client, par position : { champ => valeur }, les autres cellules vides.
  def customer(cells)
    values = Array.new(described_class::COLUMNS.size)

    described_class::COLUMNS.each do |position, field, _name|
      values[position] = cells[field]
    end

    values
  end

  # Lignes du fichier, numérotées à partir de 1.
  def rows(*lines)
    lines.each_with_index.map do |values, index|
      Importer::Adapter::Row.new(line: index + 1, values: values)
    end
  end

  def records(*lines) = described_class.new(rows(*lines)).records

  it "names the cells of each customer row" do
    record = records(header, customer(reference: "C1", last_name: "Dupont", zip: 1000)).first

    expect(record.cells).to include(reference: "C1", last_name: "Dupont", zip: 1000)
  end

  it "keeps the line number of each customer row" do
    result = records(header, customer(reference: "C1"), customer(reference: "C2"))

    expect(result.map { |record| record.line }).to eq([2, 3])
  end

  # « Nom », « Code postal »… apparaissent deux fois dans l'en-tête : facturation, puis livraison.
  it "tells billing and shipping columns apart, although their headers are identical" do
    record = records(header, customer(last_name: "Dupont", zip: 1000, shipping_last_name: "Martin", shipping_zip: 2000)).first

    expect(record.cells).to include(last_name: "Dupont", zip: 1000, shipping_last_name: "Martin", shipping_zip: 2000)
  end

  it "skips empty rows" do
    result = records(header, customer(reference: "C1"), Array.new(header.size), customer(reference: "C2"))

    expect(result.map { |record| record.cells[:reference] }).to eq(["C1", "C2"])
  end

  it "skips the TOTAL row" do
    result = records(header, customer(reference: "C1"), customer(reference: "TOTAL", company_name: "1 tiers"))

    expect(result.map { |record| record.cells[:reference] }).to eq(["C1"])
  end

  it "returns no records for a file with only a header" do
    expect(records(header)).to be_empty
  end

  describe "client file anomalies" do
    it "rejects a file without a header row" do
      expect { records }.to raise_error(Importer::FileRejected, "header row missing")
    end

    it "rejects a file whose header differs" do
      header[5] = "CP"

      expect { records(header) }
        .to raise_error(Importer::FileRejected, 'unexpected header (column 6: expected "Code postal", found "CP")')
    end
  end

  describe "#ignored_columns" do
    def ignored_columns(*lines) = described_class.new(rows(*lines)).ignored_columns

    it "returns nothing when every row fits the expected columns" do
      expect(ignored_columns(header, customer(reference: "C1"))).to be_empty
    end

    it "does not reject the file for an additional column" do
      result = records(header + ["Remarque"], customer(reference: "C1") + ["Livrer le matin"])

      expect(result.map { |record| record.cells[:reference] }).to eq(["C1"])
    end

    it "reports an additional column with its header and the number of filled rows" do
      result = ignored_columns(
        header + ["Remarque"],
        customer(reference: "C1") + ["Livrer le matin"],
        customer(reference: "C2") + [nil]
      )

      expect(result).to eq([described_class::IgnoredColumn.new(position: 27, name: "Remarque", filled: 1)])
    end

    it "reports an additional column with a header but no value" do
      result = ignored_columns(header + ["Remarque"], customer(reference: "C1"))

      expect(result).to eq([described_class::IgnoredColumn.new(position: 27, name: "Remarque", filled: 0)])
    end

    # Des valeurs sans en-tête seraient perdues sans laisser de trace.
    it "reports values found beyond the header" do
      result = ignored_columns(
        header,
        customer(reference: "C1") + ["Livrer le matin"],
        customer(reference: "C2") + ["Fermé le lundi"]
      )

      expect(result).to eq([described_class::IgnoredColumn.new(position: 27, name: nil, filled: 2)])
    end

    it "reports each additional column separately" do
      result = ignored_columns(
        header + ["Remarque"],
        customer(reference: "C1") + ["Livrer le matin", "Fermé le lundi"]
      )

      expect(result).to eq([
        described_class::IgnoredColumn.new(position: 27, name: "Remarque", filled: 1),
        described_class::IgnoredColumn.new(position: 28, name: nil, filled: 1)
      ])
    end

    it "ignores empty cells beyond the expected columns" do
      result = ignored_columns(header + [nil], customer(reference: "C1") + [nil, nil])

      expect(result).to be_empty
    end
    end

  describe "with the client's customers export" do
    before(:all) do
      rows             = Importer::Adapter::Xlsx.new(data_path("export_clients_cavegest.xlsx"), sheet: "Feuil1").rows
      layout           = described_class.new(rows)
      @records         = layout.records
      @ignored_columns = layout.ignored_columns
    end

    let(:records) { @records }

    # 5 003 lignes : l'en-tête, 4 997 clients, 4 lignes vides et la ligne TOTAL.
    it "reads every customer row" do
      expect(records.size).to eq(4997)
      expect(records.first).to have_attributes(line: 2, cells: include(reference: "T00001"))
      expect(records.last).to have_attributes(line: 5001, cells: include(reference: "T05000"))
    end

    it "reads the billing and shipping postal codes from their own columns" do
      record = records.find { |candidate| candidate.cells[:reference] == "T00013" }

      expect(record.cells).to include(zip: 4000, shipping_zip: 11100)
    end

    it "has no column beyond the expected ones" do
      expect(@ignored_columns).to be_empty
    end
  end
end
