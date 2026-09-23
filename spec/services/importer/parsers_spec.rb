require "spec_helper"

RSpec.describe Importer::Parsers do
  include Dry::Monads[:result]

  describe ".text" do
    it "strips surrounding whitespace" do
      expect(described_class.text("  Dupont  ")).to eq(Success(described_class::Parsed.new(value: "Dupont")))
    end

    [nil, "", "   "].each do |raw|
      it "reads #{raw.inspect} as an empty value" do
        expect(described_class.text(raw)).to eq(Success(described_class::Parsed.new(value: nil)))
      end
    end
  end

  describe ".zip" do
    context "in France" do
      it "keeps a 5-digit postal code" do
        expect(described_class.zip(75001, "FR")).to eq(Success(described_class::Parsed.new(value: "75001")))
      end

      it "reads a postal code stored as text" do
        expect(described_class.zip(" 01000 ", "FR")).to eq(Success(described_class::Parsed.new(value: "01000")))
      end

      it "restores the leading zero lost by Excel" do
        expect(described_class.zip(1000, "FR")).to eq(Success(described_class::Parsed.new(value: "01000", notice: :zip_padded)))
      end

      [100, 123456, "7500A", "75 01", "-7500", "1_000"].each do |raw|
        it "fails on #{raw.inspect}" do
          expect(described_class.zip(raw, "FR")).to eq(Failure(:zip_invalid))
        end
      end
    end

    context "in Belgium" do
      it "keeps a 4-digit postal code as is" do
        expect(described_class.zip(1000, "BE")).to eq(Success(described_class::Parsed.new(value: "1000")))
      end

      it "fails on a 5-digit postal code" do
        expect(described_class.zip(10000, "BE")).to eq(Failure(:zip_invalid))
      end
    end

    it "keeps the value as is for a country without a known rule" do
      expect(described_class.zip("10000", "DE")).to eq(Success(described_class::Parsed.new(value: "10000")))
    end

    it "does not guess a rule when the country is unknown" do
      expect(described_class.zip(1000, nil)).to eq(Success(described_class::Parsed.new(value: "1000")))
    end

    it "reads an empty cell as an empty value" do
      expect(described_class.zip(nil, "FR")).to eq(Success(described_class::Parsed.new(value: nil)))
    end

    it "fails on a decimal number rather than producing a '.0' suffix" do
      expect(described_class.zip(1000.0, "FR")).to eq(Failure(:zip_invalid))
    end
    end

  describe ".country_code" do
    { "FR" => "FR", " fr " => "FR", "France" => "FR", "FRANCE" => "FR",
      "Allemagne" => "DE", "Germany" => "DE", "ES" => "ES", "Espagne" => "ES" }.each do |raw, code|
        it "reads #{raw.inspect} as #{code}" do
          expect(described_class.country_code(raw)).to eq(Success(described_class::Parsed.new(value: code)))
        end
      end

    it "reads an empty cell as an empty value" do
      expect(described_class.country_code(nil)).to eq(Success(described_class::Parsed.new(value: nil)))
    end

    ["XX", "Atlantide"].each do |raw|
      it "fails on #{raw.inspect} rather than truncating it" do
        expect(described_class.country_code(raw)).to eq(Failure(:country_unknown))
      end
    end
  end

  describe ".phone" do
    context "with France as the default country" do
      def phone(raw) = described_class.phone(raw, default_country: "FR")

      { "01 23 45 67 89"    => "+33123456789",
        "01.23.45.67.89"    => "+33123456789",
        "01-23-45-67-89"    => "+33123456789",
        "+33 1 23 45 67 89" => "+33123456789",
        "06 12 34 56 78"    => "+33612345678" }.each do |raw, number|
          it "reads #{raw.inspect}" do
            expect(phone(raw)).to eq(Success(described_class::Parsed.new(value: number)))
          end
        end

        it "restores the leading zero of a number stored as a number by Excel" do
          expect(phone(123456789)).to eq(Success(described_class::Parsed.new(value: "+33123456789", notice:
                                                                             :phone_leading_zero_restored)))
        end

        it "reads a foreign number written in international format" do
          expect(phone("+32 2 555 12 34")).to eq(Success(described_class::Parsed.new(value: "+3225551234")))
        end

        # 0690 : plage de mobiles de Guadeloupe, qui dépend de l'indicatif +590 et non de +33.
        it "keeps a number outside the assigned ranges, with a notice" do
          expect(phone("06 90 12 34 56")).to eq(Success(described_class::Parsed.new(value: "+33690123456", notice: :phone_unassigned)))
        end

        [nil, "", "  "].each do |raw|
          it "reads #{raw.inspect} as an empty value" do
            expect(phone(raw)).to eq(Success(described_class::Parsed.new(value: nil)))
          end
        end

        # Les marqueurs de valeur absente sont propres à chaque logiciel : ils sont traités avant le parser.
        it "does not know the empty markers of a source software" do
          expect(phone("N/C")).to eq(Failure(:phone_invalid))
        end

        ["12345", "01 23 45 67 89 00 00", "pas de téléphone", 1234.5].each do |raw|
          it "fails on #{raw.inspect}" do
            expect(phone(raw)).to eq(Failure(:phone_invalid))
          end
        end
    end

    context "with Belgium as the default country" do
      it "reads a number written without international prefix" do
        expect(described_class.phone("02 555 12 34", default_country: "BE"))
          .to eq(Success(described_class::Parsed.new(value: "+3225551234")))
      end

      # Restaurer un zéro initial n'a de sens que pour la numérotation française.
      it "does not restore a leading zero" do
        expect(described_class.phone("123456789", default_country: "BE"))
          .to eq(Success(described_class::Parsed.new(value: "+32123456789", notice: :phone_unassigned)))
      end
    end
  end

  describe ".email" do
    it "strips surrounding whitespace" do
      expect(described_class.email("  jean@exemple.fr  ")).to eq(Success(described_class::Parsed.new(value: "jean@exemple.fr")))
    end

    it "reads an empty cell as an empty value" do
      expect(described_class.email(nil)).to eq(Success(described_class::Parsed.new(value: nil)))
    end

    it "accepts a domain with several levels" do
      expect(described_class.email("jean@mail.exemple.fr")).to eq(Success(described_class::Parsed.new(value:
                                                                                                      "jean@mail.exemple.fr")))
    end

    ["jean@", "exemple.fr", "jean dupont@exemple.fr", "jean@@exemple.fr", "jean@.fr", "jean@exemple."].each do |raw|
      it "fails on #{raw.inspect}" do
        expect(described_class.email(raw)).to eq(Failure(:email_invalid))
      end
    end

    # Adresses acceptées par la norme HTML, mais qui ne permettent pas de joindre le client.
    ["jean@exemple", "jean@exemple.f"].each do |raw|
      it "fails on #{raw.inspect}, whose domain has no usable extension" do
        expect(described_class.email(raw)).to eq(Failure(:email_invalid))
      end
    end
  end

  describe ".date" do
    it "keeps a date already read as a date, whatever the format" do
      expect(described_class.date(Date.new(2020, 1, 1), format: "%d/%m/%Y"))
        .to eq(Success(described_class::Parsed.new(value: Date.new(2020, 1, 1))))
    end

    context "with the dd/mm/yyyy format" do
      def date(raw) = described_class.date(raw, format: "%d/%m/%Y")

      it "reads a date" do
        expect(date("01/02/2020")).to eq(Success(described_class::Parsed.new(value: Date.new(2020, 2, 1))))
      end

      [nil, "", "  "].each do |raw|
        it "reads #{raw.inspect} as an empty value" do
          expect(date(raw)).to eq(Success(described_class::Parsed.new(value: nil)))
        end
      end

      # Date.strptime lirait "01/02/20" comme l'an 20 et ignorerait " abc".
      ["31/02/2020", "2020-02-01", "01/02/20", "01/02/2020 abc", "1/2/2020", 43831].each do |raw|
        it "fails on #{raw.inspect}" do
          expect(date(raw)).to eq(Failure(:date_invalid))
        end
      end
    end

    context "with the yyyy-mm-dd format" do
      def date(raw) = described_class.date(raw, format: "%Y-%m-%d")

      it "reads a date" do
        expect(date("2020-02-01")).to eq(Success(described_class::Parsed.new(value: Date.new(2020, 2, 1))))
      end

      it "fails on a date in another format" do
        expect(date("01/02/2020")).to eq(Failure(:date_invalid))
      end
    end
  end

  describe ".flag" do
    context "with 0 / 1 values" do
      def flag(raw) = described_class.flag(raw, true_values: [1, "1"], false_values: [0, "0"])

      [[0, false], ["0", false], [1, true], ["1", true]].each do |raw, value|
        it "reads #{raw.inspect} as #{value}" do
          expect(flag(raw)).to eq(Success(described_class::Parsed.new(value: value)))
        end
      end

      [nil, 2, "oui"].each do |raw|
        it "fails on #{raw.inspect}" do
          expect(flag(raw)).to eq(Failure(:flag_invalid))
        end
      end
    end

    context "with oui / non values" do
      def flag(raw) = described_class.flag(raw, true_values: ["oui"], false_values: ["non"])

      it "reads the values given by the caller" do
        expect(flag("oui")).to eq(Success(described_class::Parsed.new(value: true)))
        expect(flag("non")).to eq(Success(described_class::Parsed.new(value: false)))
      end

      it "fails on values meaningful for another software" do
        expect(flag(1)).to eq(Failure(:flag_invalid))
      end
    end
  end

  describe ".money" do
    { "13"           => BigDecimal("13"),
      "13,32"        => BigDecimal("13.32"),
      "13.32"        => BigDecimal("13.32"),
      "  19,31 EUR"  => BigDecimal("19.31"),
      "10 €"         => BigDecimal("10"),
      "0,00"         => BigDecimal("0"),
      13             => BigDecimal("13") }.each do |raw, amount|
      it "reads #{raw.inspect}" do
        expect(described_class.money(raw)).to eq(Success(described_class::Parsed.new(value: amount)))
      end
    end

    it "returns a BigDecimal, never a Float" do
      expect(described_class.money("13,32").value!.value).to be_a(BigDecimal)
    end

    [nil, "", "  "].each do |raw|
      it "reads #{raw.inspect} as an empty value, not as zero" do
        expect(described_class.money(raw)).to eq(Success(described_class::Parsed.new(value: nil)))
      end
    end

    ["-5", "1_000", "1e3", "1.000,50", ".5", "5.", "treize", 13.5].each do |raw|
      it "fails on #{raw.inspect}" do
        expect(described_class.money(raw)).to eq(Failure(:amount_invalid))
      end
    end
  end

  describe ".vat_rate" do
    { "20" => BigDecimal("20"), "20%" => BigDecimal("20"), "20 %" => BigDecimal("20"),
      "5,50" => BigDecimal("5.5"), "5.5" => BigDecimal("5.5"), "10" => BigDecimal("10"), "2,1" => BigDecimal("2.1") }.each do |raw, rate|
      it "reads #{raw.inspect}" do
        expect(described_class.vat_rate(raw)).to eq(Success(described_class::Parsed.new(value: rate)))
      end
    end

    it "reads an empty cell as an empty value" do
      expect(described_class.vat_rate(nil)).to eq(Success(described_class::Parsed.new(value: nil)))
    end

    it "fails on an unreadable rate" do
      expect(described_class.vat_rate("vingt")).to eq(Failure(:vat_rate_invalid))
    end

    it "fails on a rate that does not exist in France" do
      expect(described_class.vat_rate("19,6")).to eq(Failure(:vat_rate_unknown))
    end
  end

  describe ".integer" do
    { "28" => 28, " 28 " => 28, "-3" => -3, 28 => 28 }.each do |raw, number|
      it "reads #{raw.inspect}" do
        expect(described_class.integer(raw)).to eq(Success(described_class::Parsed.new(value: number)))
      end
    end

    it "reads an empty cell as an empty value" do
      expect(described_class.integer("")).to eq(Success(described_class::Parsed.new(value: nil)))
    end

    ["2,5", "-", "douze", 2.5].each do |raw|
      it "fails on #{raw.inspect}" do
        expect(described_class.integer(raw)).to eq(Failure(:integer_invalid))
      end
    end
  end

  describe ".term" do
    def color(raw) = described_class.term(raw, terms: { "rouge" => "red", "rosé" => "rose" }, failure: :color_unknown)

    ["rouge", "Rouge", "ROUGE", " rouge "].each do |raw|
      it "reads #{raw.inspect}, whatever its case" do
        expect(color(raw)).to eq(Success(described_class::Parsed.new(value: "red")))
      end
    end

    it "reads an accented term" do
      expect(color("Rosé")).to eq(Success(described_class::Parsed.new(value: "rose")))
    end

    it "reads an empty cell as an empty value" do
      expect(color(nil)).to eq(Success(described_class::Parsed.new(value: nil)))
    end

    it "fails with the given code on an unknown term" do
      expect(color("vert")).to eq(Failure(:color_unknown))
    end
  end

  describe ".vintage" do
    { "Coteaux Nord 2019" => "2019", "Haut Montcalm N.M." => nil, "Cuvée Marie" => nil, "Cuvée 12345" => nil, nil => nil }
      .each do |name, vintage|
        it "reads #{vintage.inspect} in #{name.inspect}" do
          expect(described_class.vintage(name)).to eq(Success(described_class::Parsed.new(value: vintage)))
        end
      end
  end

  describe ".container" do
    def container(raw)
      described_class.container(raw, types: { "Bouteille" => "bottle", "½ Bouteille" => "bottle", "Carton" => "case" },
                                     case_type: "case", volume_unit_ml: 10)
    end

    it "reads a single unit and its volume" do
      expect(container("Bouteille - 75.0"))
        .to eq(Success(described_class::Parsed.new(value: { type: "bottle", units: 1, volume_ml: 750 })))
    end

    it "reads a half volume" do
      expect(container("½ Bouteille - 37.5"))
        .to eq(Success(described_class::Parsed.new(value: { type: "bottle", units: 1, volume_ml: 375 })))
    end

    it "reads a number of units and their volume as a case, with a notice" do
      expect(container("6 x 75"))
        .to eq(Success(described_class::Parsed.new(value: { type: "case", units: 6, volume_ml: 750 }, notice: :container_read_as_case)))
    end

    # Le nombre d'unités est écrit, pas leur volume : on garde ce qui est connu, et on signale le reste.
    it "reads a case without the volume of its units, with a notice" do
      expect(container("Carton 6"))
        .to eq(Success(described_class::Parsed.new(value: { type: "case", units: 6, volume_ml: nil }, notice: :container_volume_missing)))
    end

    it "reads an empty cell as an empty value" do
      expect(container(nil)).to eq(Success(described_class::Parsed.new(value: nil)))
    end

    ["Jéroboam - 300.0", "Bouteille - soixante-quinze", "0 x 75", "Carton", "6 x", "Fût"].each do |raw|
      it "fails on #{raw.inspect}" do
        expect(container(raw)).to eq(Failure(:container_invalid))
      end
    end
  end

  describe ".label" do
    # Le même code famille arrive avec plusieurs orthographes : « Client France » et « CLIENT FRANCE ».
    ["Client France", "CLIENT FRANCE", "  client france  "].each do |raw|
      it "reads #{raw.inspect} as a single label" do
        expect(described_class.label(raw)).to eq(Success(described_class::Parsed.new(value: "CLIENT FRANCE")))
      end
    end

    it "reads an empty cell as an empty value" do
      expect(described_class.label("  ")).to eq(Success(described_class::Parsed.new(value: nil)))
    end
  end
end
