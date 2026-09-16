require "spec_helper"

RSpec.describe Importer::Normalization do
  describe ".decimal" do
    it "parses the comma decimal separator" do
      expect(described_class.decimal("13,32")).to eq(BigDecimal("13.32"))
    end

    it "parses an amount with leading spaces and an EUR suffix" do
      expect(described_class.decimal("  19,31 EUR")).to eq(BigDecimal("19.31"))
    end

    it "does not turn an empty cell into zero" do
      expect(described_class.decimal("")).to be_nil
    end

    it "does not return a Float" do
      expect(described_class.decimal("13,32")).to be_a(BigDecimal)
    end
  end

  describe ".text" do
    it "returns nil for an empty cell" do
      expect(described_class.text("")).to be_nil
    end

    it "returns nil for a whitespace-only cell" do
      expect(described_class.text("   ")).to be_nil
    end
  end

  describe ".zip" do
    it "keeps leading 0" do
      expect(described_class.zip("01000", "FR")).to eq("01000")
    end

    it "inserts leading 0 when relevant" do
      expect(described_class.zip(1000, "FR")).to eq("01000")
    end

    it "does not produce a '.0' suffix for a float numeric cell" do
      expect(described_class.zip(40000.0, "FR")).to eq("40000")
    end

    # Garde-fou (passe aujourd'hui) : la correction du zéro initial ne doit pas invalider ce test.
    it "does not pad a Belgian postal code, which legitimately has 4 digits" do
      expect(described_class.zip(1000, "BE")).to eq("1000")
    end
  end

  describe ".country_code" do
    it "converts a country name into an ISO 3166-1 alpha-2 code" do
      expect(described_class.country_code("Allemagne")).to eq("DE")
    end

    it "returns nil when the country is missing" do
      expect(described_class.country_code(nil)).to be_nil
    end
  end
end
