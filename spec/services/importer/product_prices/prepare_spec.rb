require "spec_helper"

RSpec.describe Importer::ProductPrices::Prepare do
  let(:layout_class) { Importer::Cavegest::ProductPricesLayout }
  let(:header)       { layout_class::COLUMNS.map { |_position, _field, name| name } }
  let(:report)       { MigrationReport.new }

  # Valeurs d'une ligne de l'export des tarifs CaveGest : un produit valide, modifié par `cells`.
  def product_row(cells = {})
    defaults = { reference: "REF1", name: "Vin rouge 2020", container: "Bouteille - 75.0", color: "Rouge",
                 vat_rate: "20", price_depc: "10,00", price_chr: "9,00", price_expo: "12,00", price_part: "15,00",
                 price_salon: "14,00", stock: "12" }
    values   = Array.new(layout_class::COLUMNS.size)

    layout_class::COLUMNS.each do |position, field, _name|
      values[position] = defaults.merge(cells)[field]
    end

    values
  end

  # Importe ces lignes, dans la section donnée, comme si elles étaient lues dans le fichier "tarifs.csv".
  def import(lines, section: "AOP ROUGES", header_row: header)
    preamble = [["CaveGest 4.2 - Export des grilles tarifaires"], []]
    title    = product_row.map { nil }.tap { |values| values[0] = "--- #{section} ---" }
    adapter  = double("adapter", rows: rows(preamble + [header_row, title] + lines), file_name: "tarifs.csv")

    described_class.new(adapter: adapter, layout_class: layout_class, report: report).call
  end

  def accepted_with(section: "AOP ROUGES", **cells) = import([product_row(cells)], section: section).first

  def issue(code)
    report.issues.find { |candidate| candidate.code == code }
  end

  def price(accepted, grid_code)
    accepted.prices.find { |candidate| candidate[:grid_code] == grid_code }&.fetch(:amount_ht)
  end

  describe "product" do
    it "returns the attributes of the product, with its original record" do
      accepted = accepted_with(reference: "REF1", name: "Vin rouge 2020", stock: "12")

      expect(accepted.record.line).to eq(5)
      expect(accepted.product).to include(reference: "REF1", name: "Vin rouge 2020", vintage: "2020",
                                          color: "red", vat_rate: BigDecimal("20"), stock: 12)
    end

    it "keeps the name as written, and reads the vintage at its end" do
      expect(accepted_with(name: "Cuvée Marie N.M.").product).to include(name: "Cuvée Marie N.M.", vintage: nil)
    end

    it "returns every attribute written in the database" do
      expect(accepted_with.product.keys).to match_array(Importer::ProductPrices.product_attributes)
    end

    it "does not write anything in the database" do
      expect { import([product_row]) }.not_to change(Product, :count)
    end

    describe "container" do
      it "keeps the container as written, and reads its type, units and volume" do
        expect(accepted_with(container: "Magnum - 150.0").product)
          .to include(container_label: "Magnum - 150.0", container_type: "bottle", units_per_container: 1, volume_ml: 1500)
      end

      it "reads a case of units whose volume is written, and reports it" do
        expect(accepted_with(container: "6 x 75").product).to include(container_type: "case", units_per_container: 6, volume_ml: 750)
        expect(issue(:container_read_as_case)).to have_attributes(level: :repaired, raw: "6 x 75")
      end

      it "keeps what is known of a case whose unit volume is missing, and reports what is missing" do
        expect(accepted_with(container: "Carton 6").product)
          .to include(container_label: "Carton 6", container_type: "case", units_per_container: 6, volume_ml: nil)
        expect(issue(:container_volume_missing)).to have_attributes(level: :suspect, raw: "Carton 6")
      end

      it "keeps an unreadable container as written, and reports it" do
        expect(accepted_with(container: "Fût").product).to include(container_label: "Fût", container_type: nil)
        expect(issue(:container_invalid)).to have_attributes(level: :suspect, raw: "Fût")
      end
    end

    # Sans contenant, on ne connaît ni le volume vendu ni le conditionnement : le client doit compléter.
    it "reports a product without any container" do
      expect(accepted_with(container: nil).product).to include(container_label: nil, container_type: nil)
      expect(issue(:container_missing)).to have_attributes(level: :suspect, field: :container_label)
    end

    it "reports a product without any color" do
      expect(accepted_with(color: nil).product).to include(color: nil)
      expect(issue(:color_missing)).to have_attributes(level: :info, field: :color)
    end

    it "empties an unknown color, and reports it" do
      expect(accepted_with(color: "Vert").product).to include(color: nil)
      expect(issue(:color_unknown)).to have_attributes(level: :suspect, field: :color, raw: "Vert")
    end

    describe "classification" do
      it "reads the appellation and the type of product from the section" do
        expect(accepted_with(section: "IGP").product).to include(appellation: "igp", product_type: "still_wine")
      end

      it "reads a section without appellation" do
        expect(accepted_with(section: "EFFERVESCENTS").product).to include(appellation: nil, product_type: "sparkling_wine")
      end

      # Le nom de la section annonce une couleur : les deux valeurs sont reprises, le désaccord est signalé.
      it "reports a color that contradicts its section" do
        expect(accepted_with(section: "AOP ROUGES", color: "Blanc").product).to include(color: "white")
        expect(issue(:color_inconsistent_with_section))
          .to have_attributes(level: :suspect, field: :color, raw: "Blanc", value: "white")
      end

      it "accepts a color its section announces" do
        accepted_with(section: "AOP ROUGES", color: "Rouge")

        expect(issue(:color_inconsistent_with_section)).to be_nil
      end

      it "checks no color in a section that announces none" do
        accepted_with(section: "IGP", color: "Blanc")

        expect(issue(:color_inconsistent_with_section)).to be_nil
      end

      it "reports an unknown section" do
        expect(accepted_with(section: "SPIRITUEUX").product).to include(appellation: nil, product_type: nil)
        expect(issue(:section_unknown)).to have_attributes(level: :suspect, raw: "SPIRITUEUX")
      end
    end
  end

  describe "prices" do
    it "returns one price per filled grid" do
      expect(accepted_with.prices.map { |candidate| candidate[:grid_code] }).to eq(["DEPC", "CHR", "EXPO", "PART", "SALON"])
    end

    it "reads prices written with a comma, spaces and a currency" do
      expect(price(accepted_with(price_depc: "  10,50 EUR"), "DEPC")).to eq(BigDecimal("10.50"))
    end

    it "creates no price for an empty grid, instead of a zero price, and reports it" do
      accepted = accepted_with(price_salon: nil)

      expect(price(accepted, "SALON")).to be_nil
      expect(issue(:price_grid_empty)).to have_attributes(level: :info, field: :price_salon)
    end

    # Un tarif en base sur l'une de ces grilles sera retiré ; une grille illisible n'en fait pas partie.
    it "lists the empty grids, but not the unreadable ones" do
      expect(accepted_with(price_salon: nil, price_part: "quinze").empty_grids).to eq(["SALON"])
    end

    it "rejects an unreadable price, but keeps the product and its other prices" do
      accepted = accepted_with(price_part: "quinze")

      expect(price(accepted, "PART")).to be_nil
      expect(price(accepted, "DEPC")).to eq(BigDecimal("10"))
      expect(issue(:amount_invalid)).to have_attributes(level: :rejected, field: :price_part, raw: "quinze")
    end

    it "rejects a zero price" do
      expect(price(accepted_with(price_chr: "0,00"), "CHR")).to be_nil
      expect(issue(:amount_not_positive)).to have_attributes(level: :rejected, field: :price_chr)
    end

    describe "grid entered including tax" do
      it "converts it with the VAT rate of the product, and reports it" do
        accepted = accepted_with(vat_rate: "20", price_depc: "10,00", price_expo: "12,00")

        expect(price(accepted, "EXPO")).to eq(BigDecimal("10.00"))
        expect(issue(:price_ttc_converted)).to have_attributes(level: :repaired, field: :price_expo, raw: "12,00", value: BigDecimal("10.00"))
      end

      it "uses the reduced rate of the product" do
        expect(price(accepted_with(vat_rate: "5,50", price_depc: "10,00", price_expo: "10,55"), "EXPO")).to eq(BigDecimal("10.00"))
      end

      # Dans l'export, EXPO converti en HT est égal à DEPC : un écart signale une probable erreur de saisie.
      it "reports a price that differs from the one it should equal" do
        accepted_with(price_depc: "30,00", price_expo: "12,00")

        expect(issue(:price_grids_inconsistent))
          .to have_attributes(level: :suspect, field: :price_depc, raw: "30,00", value: BigDecimal("10.00"))
      end

      it "tolerates a rounding difference of one cent" do
        accepted_with(vat_rate: "20", price_depc: "13,32", price_expo: "15,98")

        expect(issue(:price_grids_inconsistent)).to be_nil
      end
    end
  end

  describe "rejected rows" do
    { reference: :reference_missing, name: :name_missing }.each do |field, code|
      it "rejects a product without #{field}" do
        expect(import([product_row(field => nil)])).to be_empty
        expect(issue(code)).to have_attributes(level: :rejected, line: 5)
      end
    end

    # Sans taux de TVA, le prix saisi TTC ne peut pas être converti.
    [nil, "19,6", "vingt"].each do |vat_rate|
      it "rejects a product whose VAT rate is #{vat_rate.inspect}" do
        expect(import([product_row(vat_rate: vat_rate)])).to be_empty
        expect(issue(:vat_rate_missing)).to have_attributes(level: :rejected, raw: vat_rate)
      end
    end

    it "reports only the reasons of the rejection" do
      import([product_row(name: nil, color: "Vert", price_salon: nil)])

      expect(report.issues.map { |candidate| candidate.code }).to eq([:name_missing])
    end
  end

  it "rejects the whole file when its header differs, and reports why" do
    expect(import([product_row], header_row: ["Autre"] + header.drop(1))).to be_empty
    expect(issue(:file_rejected)).to have_attributes(level: :rejected, source: "tarifs.csv")
  end

  describe "with the client's price list export" do
    before(:all) do
      @report   = MigrationReport.new
      adapter   = Importer::Adapter::Csv.new(data_path("export_tarifs_cavegest.csv"),
                                            fallback_encoding: Importer::Cavegest::ProductPricesLayout::FALLBACK_ENCODING,
                                            col_sep: Importer::Cavegest::ProductPricesLayout::COL_SEP)
      @accepted = described_class.new(adapter: adapter, layout_class: Importer::Cavegest::ProductPricesLayout,
                                       report: @report).call
    end

    it "accepts every product" do
      expect(@accepted.size).to eq(113)
    end

    # 113 produits sur 5 grilles, moins 63 grilles vides.
    it "reads every filled price" do
      expect(@accepted.sum { |accepted| accepted.prices.size }).to eq(502)
    end

    it "converts every EXPO price to its DEPC price, but one" do
      cot196 = @accepted.find { |accepted| accepted.product[:reference] == "COT196" }

      expect(cot196.prices.find { |candidate| candidate[:grid_code] == "EXPO" }[:amount_ht]).to eq(BigDecimal("19.31"))
    end

    it "reports the corrections and the doubtful values found in the export" do
      counts = @report.issues.group_by { |candidate| [candidate.level, candidate.code] }.transform_values(&:size)

      expect(counts).to eq(
        [:repaired, :price_ttc_converted]             => 113,
        [:repaired, :container_read_as_case]          => 1,
        [:suspect,  :container_volume_missing]        => 1,
        [:suspect,  :price_grids_inconsistent]        => 1,
        [:suspect,  :container_missing]               => 13,
        [:suspect,  :color_inconsistent_with_section] => 16,
        [:info,     :color_missing]                   => 15,
        [:info,     :price_grid_empty]                => 63
      )
    end

    # DEPC saisi à 34,35 € alors qu'EXPO converti en HT donne 7,37 € : probable erreur de saisie.
    it "reports the inconsistent price of HAU214" do
      inconsistency = @report.issues.find { |candidate| candidate.code == :price_grids_inconsistent }

      expect(inconsistency).to have_attributes(line: 72, entity: "Produit HAU214", raw: "34,35", value: BigDecimal("7.37"))
    end
  end
end
