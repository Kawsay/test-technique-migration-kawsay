  require "spec_helper"

  RSpec.describe Importer::Adapter::Csv do
    # Fichier de test, écrit tel quel : content est une chaîne encodée comme le serait l'export.
    def csv_file(content)
      path = File.join(Dir.mktmpdir, "produits.csv")
      File.binwrite(path, content)
      path
    end

    def read(content)
      described_class.new(csv_file(content), fallback_encoding: "Windows-1252", col_sep: ";").rows
    end

    # Lignes séparées par des retours chariot Windows, encodées en Windows-1252, comme l'export CaveGest.
    def file_with(rows)
      content = rows.map { |values| values.join(";") }.join("\r\n") + "\r\n"
      described_class.new(csv_file(content.encode("Windows-1252")), fallback_encoding: "Windows-1252", col_sep: ";")
    end

    it_behaves_like "an adapter"

    it "keeps the difference between an empty field and an empty quoted field" do
      expect(read("REF1;;\"\";Rouge\r\n").first.values).to eq(["REF1", nil, "", "Rouge"])
    end

    # Une valeur entre guillemets peut contenir un retour à la ligne : l'enregistrement occupe deux lignes.
    it "numbers each row with its first line in the file" do
      rows = read("Ref;Nom\r\n\"REF1\";\"Vin\r\nrouge\"\r\nREF2;Blanc\r\n")

      expect(rows.map { |row| [row.line, row.values.first] }).to eq([[1, "Ref"], [2, "REF1"], [4, "REF2"]])
    end

    it "reads a last line without line break" do
      expect(read("Ref\r\nREF1").map { |row| row.values }).to eq([["Ref"], ["REF1"]])
    end

    describe "encoding" do
      # [encodage du fichier, contenu du fichier, valeurs attendues]
      [
        ["Windows-1252",     "Désignation;Rosé;10 €\r\n".encode("Windows-1252"), ["Désignation", "Rosé", "10 €"]],
        ["UTF-8",            "Désignation;Rosé;10 €\r\n",                         ["Désignation", "Rosé", "10 €"]],
        ["UTF-8 with a BOM", "\uFEFFDésignation;Rosé;10 €\r\n",                   ["Désignation", "Rosé", "10 €"]],
        ["ASCII",            "Designation;Rose;10 EUR\r\n",                       ["Designation", "Rose", "10 EUR"]]
      ].each do |encoding, content, expected|
        it "reads a file encoded in #{encoding}, and returns UTF-8 values" do
          values = read(content).first.values

          expect(values).to eq(expected)
          expect(values).to all(have_attributes(encoding: Encoding::UTF_8))
        end
      end

      # Limite assumée : ces octets sont de l'UTF-8 valide, le fichier est donc lu comme tel.
      it "reads a Windows-1252 file containing a valid UTF-8 sequence as UTF-8" do
        expect(read("Ã©\r\n".encode("Windows-1252")).first.values).to eq(["é"])
      end
    end

    describe "client file anomalies" do
      it "rejects a missing file" do
        path = File.join(Dir.mktmpdir, "produits.csv")

        expect { described_class.new(path, fallback_encoding: "Windows-1252", col_sep: ";").rows }
          .to raise_error(Importer::FileRejected, "produits.csv is missing")
      end

      it "rejects a file with an unclosed quote" do
        expect { read("Ref;Nom\r\nREF1;\"Vin rouge\r\n") }
          .to raise_error(Importer::FileRejected, /produits.csv is not a readable CSV file/)
      end

      # 0x81 n'est pas de l'UTF-8 valide, et n'existe pas en Windows-1252.
      it "rejects a file that is neither UTF-8 nor in the fallback encoding" do
        expect { read("REF1;\x81\r\n".b) }
          .to raise_error(Importer::FileRejected, "produits.csv is neither UTF-8 nor Windows-1252")
      end
    end

    describe "with the client's price list export" do
      before(:all) do
        @rows = described_class.new(data_path("export_tarifs_cavegest.csv"), fallback_encoding: "Windows-1252", col_sep: ";").rows
      end

      it "reads every line of the file" do
        expect(@rows.size).to eq(129)
        expect(@rows.map { |row| row.line }).to eq((1..129).to_a)
      end

      it "reads the header with its accents" do
        expect(@rows.find { |row| row.line == 3 }.values)
          .to eq(
            [
              "Ref",
              "Désignation",
              "Contenant",
              "Couleur",
              "TVA",
              "DEPC",
              "CHR",
              "EXPO",
              "PART",
              "SALON",
              "Stock"
            ]
          )
      end

      it "keeps the empty lines" do
        expect(@rows.select { |row| row.values.empty? }.map { |row| row.line }).to eq([2, 39])
      end

      it "reads the same rows when the file is converted to UTF-8" do
        converted = File.binread(data_path("export_tarifs_cavegest.csv")).force_encoding("Windows-1252").encode("UTF-8")
        adapter   = described_class.new(csv_file(converted), fallback_encoding: "Windows-1252", col_sep: ";")

        expect(adapter.rows).to eq(@rows)
      end

      it "keeps the values as written in the file" do
        product = @rows.find { |row| row.values.first == "COT196" }

        expect(product.values).to eq(
          [
            "COT196",
            "Coteaux Nord 2019",
            "Bouteille - 75.0",
            "Rouge",
            "20",
            "  19,31 EUR",
            "16,99",
            "23,17",
            "22,79",
            nil,
            "28"
          ]
        )
      end
    end
  end
