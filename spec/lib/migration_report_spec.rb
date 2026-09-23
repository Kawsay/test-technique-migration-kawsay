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
          previous: nil,
          cells: nil
        )
      )
    end

    it "leaves the optional attributes empty" do
      report.add(level: :rejected, code: :import_aborted, source:)

      expect(report.issues.first)
        .to have_attributes(line: nil, entity: nil, field: nil, raw: nil, value: nil, previous: nil)
    end

    # Une valeur effacée ou remplacée en base est rapportée avec celle qu'elle remplace.
    it "records the value a record carried before the import" do
      report.add(level: :info, code: :price_removed, source:, previous: BigDecimal("14"))

      expect(report.issues.first).to have_attributes(previous: BigDecimal("14"), value: nil)
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

  describe "#issues_for_client" do
    # Un doublon n'est connu qu'à l'écriture : les anomalies de sa ligne ont déjà été journalisées.
    it "keeps only the rejection of a line that was not imported" do
      report.add(level: :repaired, code: :zip_padded, source:, line: 12)
      report.add(level: :rejected, code: :duplicate_conflict, source:, line: 12)
      report.discard_line(source, 12)

      expect(report.issues_for_client.map { |issue| issue.code }).to eq([:duplicate_conflict])
    end

    it "keeps the whole journal" do
      report.add(level: :repaired, code: :zip_padded, source:, line: 12)
      report.discard_line(source, 12)

      expect(report.issues.map { |issue| issue.code }).to eq([:zip_padded])
    end

    it "keeps the anomalies of the other lines" do
      report.add(level: :repaired, code: :zip_padded, source:, line: 13)
      report.discard_line(source, 12)

      expect(report.issues_for_client.map { |issue| issue.line }).to eq([13])
    end

    it "keeps the anomalies of the same line in another file" do
      report.add(level: :repaired, code: :zip_padded, source: "tarifs.csv", line: 12)
      report.discard_line(source, 12)

      expect(report.issues_for_client.map { |issue| issue.source }).to eq(["tarifs.csv"])
    end

    # Un tarif rejeté ne rejette pas sa ligne : le produit, lui, est en base.
    it "keeps the anomalies of a line that was imported despite a rejection" do
      report.add(level: :rejected, code: :amount_invalid, source:, line: 12)
      report.add(level: :repaired, code: :price_ttc_converted, source:, line: 12)

      expect(report.issues_for_client.map { |issue| issue.code }).to eq([:amount_invalid, :price_ttc_converted])
    end

    it "counts by level what the client is shown" do
      report.add(level: :repaired, code: :zip_padded, source:, line: 12)
      report.discard_line(source, 12)

      expect(report.by_level(:repaired)).to be_empty
    end
  end

  describe "recorded issue" do
    it "reads its message from the translations" do
      issue = report.add(level: :repaired, code: :zip_padded, source:)

      expect(issue.message).to eq("Code postal complété d'un zéro initial (perdu par Excel)")
    end

    # Un code sans libellé reste lisible, et le test des libellés le signalera.
    it "falls back to the code when it has no translation" do
      issue = report.add(level: :repaired, code: :not_translated_yet, source:)

      expect(issue.message).to eq("not_translated_yet")
    end
  end
end
