require "spec_helper"
require "caxlsx"

RSpec.describe Importer::Adapter::Xlsx do
  # Classeur de test. sheets : { "nom de la feuille" => [[valeurs de la ligne 1], [ligne 2], …] }
  def workbook(sheets)
    path = File.join(Dir.mktmpdir, "classeur.xlsx")
    Axlsx::Package.new do |package|
      sheets.each do |name, rows|
        package.workbook.add_worksheet(name:) do |sheet|
          rows.each { |values| sheet.add_row(values) }
        end
      end
      package.serialize(path)
    end
    path
  end

  def file_with(rows) = described_class.new(workbook("Produits" => rows), sheet: "Produits")

  it_behaves_like "an adapter"

  it "keeps the native type of each value" do
    expect(file_with([["REF1", nil, 10, 10.5, Date.new(2020, 1, 1)]]).rows.first.values)
      .to eq(["REF1", nil, 10, 10.5, Date.new(2020, 1, 1)])
  end

  it "reads the requested sheet, not the first one" do
    path = workbook("Archives" => [["NE PAS UTILISER"]], "Produits" => [["Ref"]])

    expect(described_class.new(path, sheet: "Produits").rows.first.values).to eq(["Ref"])
  end

  it "returns no rows for an empty sheet" do
    expect(file_with([]).rows).to be_empty
  end

  describe "client file anomalies" do
    it "rejects the file when the requested sheet is missing" do
      path = workbook("Archives" => [["Ref"]], "Clients" => [["Code"]])

      expect { described_class.new(path, sheet: "Produits").rows }
        .to raise_error(Importer::FileRejected, "classeur.xlsx, sheet Produits missing")
    end

    it "rejects a missing file" do
      path = File.join(Dir.mktmpdir, "produits.xlsx")

      expect { described_class.new(path, sheet: "Produits").rows }
        .to raise_error(Importer::FileRejected, "produits.xlsx is missing")
    end

    it "rejects a file that is not a workbook" do
      path = File.join(Dir.mktmpdir, "produits.xlsx")
      File.write(path, "Ref;Nom\nREF1;Rouge\n")

      expect { described_class.new(path, sheet: "Produits").rows }
        .to raise_error(Importer::FileRejected, "produits.xlsx is not a readable Excel workbook")
    end

    # Un fichier .xlsx est une archive zip : celle-ci est lisible mais ne contient pas de classeur.
    #
    # Ce test serait pertinent, mais Roo lève un ArgumentError qui serait trop vaste à catch.
    # https://github.com/roo-rb/roo/blob/f3e67741f5f13422e9231a9923579ff0067bdfd1/lib/roo/excelx/workbook.rb#L23
    #
    # Une solution serait de vérifier le contenu de l'erreur, mais cela rendrait notre code
    # trop rigide et trop dépendant à un détail de Roo.
    #
    # it "rejects a zip archive that does not contain a workbook" do
    #   path = File.join(Dir.mktmpdir, "produits.xlsx")
    #   Zip::File.open(path, create: true) do |zip|
    #     zip.get_output_stream("produits.txt") { |file| file.write("REF1;Rouge") }
    #   end
    #
    #   expect { described_class.new(path, sheet: "Produits").rows }
    #     .to raise_error(Importer::FileRejected, "produits.xlsx does not contain a valid workbook.xml")
    # end
  end

  describe "with the client's customers export" do
    before(:all) { @rows = described_class.new(data_path("export_clients_cavegest.xlsx"), sheet: "Feuil1").rows }

    let(:rows) { @rows }

    it "reads every line, from the header to the TOTAL row" do
      expect(rows.map { |row| row.line }).to eq((1..5003).to_a)
      expect(rows.first.values.first(3)).to eq(["Code", "Nom", "Prénom"])
      expect(rows.last.values.first).to eq("TOTAL")
    end

    # Des lignes vides sont intercalées dans l'export : les numéros de ligne doivent rester ceux du tableur.
    it "keeps the line numbers of the spreadsheet after an empty row" do
      empty_row = rows.find { |row| row.line == 602 }
      next_row  = rows.find { |row| row.line == 603 }

      expect(empty_row.values).to all(be_nil)
      expect(next_row.values.first).to eq("T00602")
    end
  end
end
