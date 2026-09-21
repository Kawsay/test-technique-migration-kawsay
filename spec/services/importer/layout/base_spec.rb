require "spec_helper"

RSpec.describe Importer::Layout::Base do
  it "requires subclasses to describe their columns" do
    layout = Class.new(described_class).new(rows([["Ref"]]))

    expect { layout.records }.to raise_error(NotImplementedError, /must implement #columns/)
  end

  # Disposition minimale : une référence et un nom.
  context "with a subclass describing its columns" do
    let(:layout_class) do
      Class.new(described_class) do
        private

        def columns
          [[0, :reference, "Ref"], [1, :name, "Nom"]]
        end
      end
    end

    let(:header) { ["Ref", "Nom"] }

    def data_row(value) = [value, "Vin rouge"]
    def layout_with(rows) = layout_class.new(rows)

    it_behaves_like "a layout"

    it "names the cells with the fields of the columns" do
      record = layout_with(rows([header, ["REF1", "Vin rouge"]])).records.first

      expect(record.cells).to eq(reference: "REF1", name: "Vin rouge")
    end

    it "keeps every non-empty row when the subclass skips no row" do
      records = layout_with(rows([header, ["TOTAL", "2 produits"]])).records

      expect(records.map { |record| record.cells[:reference] }).to eq(["TOTAL"])
    end

    it "skips no row by default" do
      expect(layout_with(rows([header, ["REF1", "Vin rouge"], []])).skipped_rows).to be_empty
    end

    context "with a subclass skipping its total rows" do
      let(:layout_class) do
        Class.new(described_class) do
          private

          def columns
            [[0, :reference, "Ref"], [1, :name, "Nom"]]
          end

          def skipped_row?(row)
            row.values.first == "TOTAL"
          end
        end
      end

      it "exposes the skipped rows, without the empty ones" do
        layout = layout_with(rows([header, ["REF1", "Vin rouge"], [], ["TOTAL", "1 produit"]]))

        expect(layout.records.map { |record| record.line }).to eq([2])
        expect(layout.skipped_rows.map { |row| [row.line, row.values] }).to eq([[4, ["TOTAL", "1 produit"]]])
      end
    end

    it "returns no records for a file with only a header" do
      expect(layout_with(rows([header])).records).to be_empty
    end

    it "lists every difference of the header" do
      expect { layout_with(rows([["Code", "Libellé"]])).records }
        .to raise_error(Importer::FileRejected, 'unexpected header (column 1: expected "Ref", found "Code"; column 2: expected "Nom", found "Libellé")')
    end

    it "rejects a file with a missing column" do
      expect { layout_with(rows([["Ref"]])).records }
        .to raise_error(Importer::FileRejected, 'unexpected header (column 2: expected "Nom", found "")')
    end

    describe "#ignored_columns" do
      def ignored_columns(lines) = layout_with(rows(lines)).ignored_columns

      it "returns nothing when every row fits the expected columns" do
        expect(ignored_columns([header, ["REF1", "Vin rouge"]])).to be_empty
      end

      it "reports an additional column with a header but no value" do
        expect(ignored_columns([header + ["Remarque"], ["REF1", "Vin rouge"]]))
          .to eq([Importer::Layout::Base::IgnoredColumn.new(position: 2, name: "Remarque", filled: 0)])
      end

      it "counts the rows where the additional column is filled" do
        result = ignored_columns([
          header + ["Remarque"],
          ["REF1", "Vin rouge", "Livrer le matin"],
          ["REF2", "Vin blanc", nil]
        ])

        expect(result).to eq([Importer::Layout::Base::IgnoredColumn.new(position: 2, name: "Remarque", filled: 1)])
      end

      # Des valeurs sans en-tête seraient perdues sans laisser de trace.
      it "reports values found beyond the header" do
        result = ignored_columns([
          header,
          ["REF1", "Vin rouge", "Livrer le matin"],
          ["REF2", "Vin blanc", "Fermé le lundi"]
        ])

        expect(result).to eq([Importer::Layout::Base::IgnoredColumn.new(position: 2, name: nil, filled: 2)])
      end

      it "reports each additional column separately" do
        result = ignored_columns([header + ["Remarque"], ["REF1", "Vin rouge", "Livrer le matin", "Fermé le lundi"]])

        expect(result).to eq([
          Importer::Layout::Base::IgnoredColumn.new(position: 2, name: "Remarque", filled: 1),
          Importer::Layout::Base::IgnoredColumn.new(position: 3, name: nil, filled: 1)
        ])
      end

      it "ignores empty cells beyond the expected columns" do
        expect(ignored_columns([header + [nil], ["REF1", "Vin rouge", nil, nil]])).to be_empty
      end
    end
  end
end
