require "spec_helper"

RSpec.describe Importer::IssuesCsv do
  let(:report) { MigrationReport.new }
  let(:source) { "clients.xlsx" }

  def rows
    CSV.parse(described_class.new(report).to_csv, col_sep: ";")
  end

  it "writes one row per issue, with its label and its values" do
    report.add(level: :repaired, code: :zip_padded, source: source, line: 12, entity: "Client C1",
               field: :zip, raw: 1000, value: "01000")

    expect(rows.first).to eq(described_class::HEADERS)
    expect(rows.last).to eq(["Repris avec correction automatique", "clients.xlsx", "12", "Client C1", "zip",
                             "Code postal complété d'un zéro initial (perdu par le tableur)", "1000", "01000", nil])
  end

  # Le client trie et filtre sur la gravité : les lignes non reprises viennent en premier.
  it "sorts the issues from the most severe to the least" do
    report.add(level: :info, code: :price_grid_empty, source: source, line: 12)
    report.add(level: :rejected, code: :name_missing, source: source, line: 13)
    report.add(level: :suspect, code: :email_invalid, source: source, line: 14)

    expect(rows.drop(1).map { |row| row[2] }).to eq(["13", "14", "12"])
  end

  it "writes an amount as the client reads it" do
    report.add(level: :info, code: :price_removed, source: source, line: 12, previous: BigDecimal("14"))

    expect(rows.last.last).to eq("14.0")
  end

  # Une ligne non reprise ne porte que son motif de rejet (voir MigrationReport#issues_for_client).
  it "leaves out the other anomalies of a discarded line" do
    report.add(level: :repaired, code: :zip_padded, source: source, line: 12)
    report.add(level: :rejected, code: :duplicate_conflict, source: source, line: 12)
    report.discard_line(source, 12)

    expect(rows.drop(1).map { |row| row[5] }).to eq(["Référence présente sur plusieurs lignes différentes"])
  end

  describe "#write" do
    it "writes a file a French spreadsheet opens correctly" do
      report.add(level: :rejected, code: :name_missing, source: source, line: 13, entity: "Client C1")
      path = described_class.new(report).write(File.join(Dir.mktmpdir, "anomalies.csv"))

      expect(File.read(path)).to start_with(described_class::BOM)
      expect(File.read(path)).to include("Non repris;clients.xlsx;13;Client C1")
    end
  end

  describe ".path_for" do
    it "names the report after its source file, and dates it" do
      path = described_class.path_for("export_clients_cavegest.xlsx", directory: "data/report")

      expect(path).to match(%r{\Adata/report/anomalies-export_clients_cavegest-\d{8}-\d{6}\.csv\z})
    end
  end
end
