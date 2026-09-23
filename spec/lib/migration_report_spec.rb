require "spec_helper"

RSpec.describe MigrationReport do
  subject(:report) { described_class.new }

  let(:source) { "export_clients_cavegest.xlsx" }

  it "starts with an empty journal" do
    expect(report.issues).to be_empty
  end

  it "does not share its journal with another report" do
    report.add(level: :info, code: :duplicate_identical, source:)

    expect(described_class.new.issues).to be_empty
  end

  describe "#add" do
    it "records an issue with its location and the before / after values" do
      report.add(
        level: :repaired,
        code: :zip_padded,
        source:,
        line: 42,
        entity: "Client 001",
        field: :zip,
        raw: 1000,
        value: "01000",
        cells: nil
      )

      expect(report.issues).to contain_exactly(
        MigrationReport::Issue.new(
          level: :repaired,
          code: :zip_padded,
          source:,
          line: 42,
          entity: "Client 001",
          field: :zip,
          raw: 1000,
          value: "01000",
          cells: nil
        )
      )
    end

    it "leaves the optional attributes empty" do
      report.add(level: :rejected, code: :import_aborted, source:)

      expect(report.issues.first).to have_attributes(line: nil, entity: nil, field: nil, raw: nil, value: nil)
    end

    it "keeps the issues in the order they were recorded" do
      report.add(level: :rejected, code: :name_missing, source:, line: 42)
      report.add(level: :repaired, code: :zip_padded,   source:, line: 12)

      expect(report.issues.map(&:line)).to eq([42, 12])
    end

    # Un journal enregistre ce qui s'est passé : deux événements identiques restent deux événements.
    it "keeps identical issues" do
      2.times { report.add(level: :repaired, code: :zip_padded, source:, line: 12) }

      expect(report.issues.size).to eq(2)
    end

    MigrationReport::LEVELS.each do |level|
      it "accepts the #{level} level" do
        expect { report.add(level:, code: :zip_padded, source:) }.to change { report.issues.size }.by(1)
      end
    end

    [:warning, "rejected", nil].each do |level|
      it "rejects the #{level.inspect} level without recording anything" do
        expect { report.add(level:, code: :zip_padded, source:) }.to raise_error(ArgumentError, /unknown level/)
        expect(report.issues).to be_empty
      end
    end

    it "requires a code" do
      expect { report.add(level: :info, source:) }.to raise_error(ArgumentError, /code/)
    end

    it "requires a source" do
      expect { report.add(level: :info, code: :zip_padded) }.to raise_error(ArgumentError, /source/)
    end

    it "rejects an unknown attribute" do
      expect { report.add(level: :info, code: :zip_padded, source:, feild: :zip) }
        .to raise_error(ArgumentError, /feild/)
    end
  end

  describe "recorded issue" do
    it "cannot be modified once recorded" do
      report.add(level: :repaired, code: :zip_padded, source:)

      expect(report.issues.first).to be_frozen
    end
  end

  describe "#record_bilan" do
    let(:bilan) { MigrationReport::Bilan.new(accepted: 2, created: 2, updated: 0, unchanged: 0) }

    it "records one bilan per file and type of record" do
      report.record_bilan(source, :products, bilan)
      report.record_bilan(source, :product_prices, bilan)

      expect(report.bilans.keys).to eq([[source, :products], [source, :product_prices]])
    end

    # Un rapport décrit une seule exécution : un rejeu s'écrit dans un nouveau rapport.
    it "refuses a second bilan for the same file and type of record" do
      report.record_bilan(source, :products, bilan)

      expect { report.record_bilan(source, :products, bilan) }.to raise_error(ArgumentError, /déjà enregistré/)
    end
  end
end
