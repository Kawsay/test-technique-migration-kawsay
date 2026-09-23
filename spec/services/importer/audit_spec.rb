require "spec_helper"

RSpec.describe Importer::Audit do
  def product(reference, attributes = {})
    Product.create!({ reference: reference, name: "Vin rouge", vat_rate: BigDecimal("20") }.merge(attributes))
  end

  def price(product, grid_code, amount)
    ProductPrice.create!(product: product, grid_code: grid_code, amount_ht: BigDecimal(amount))
  end

  def customer(reference, attributes = {})
    Customer.create!({ reference: reference, company_name: "Cave Dupont" }.merge(attributes))
  end

  def finding(label, equal_price_grids: [])
    described_class.new(equal_price_grids: equal_price_grids).call.find { |candidate| candidate.label.start_with?(label) }
  end

  describe "products and their prices" do
    it "accepts a product that has a price" do
      price(product("REF1"), "DEPC", "10.00")

      expect(finding("Chaque produit a au moins un tarif")).to be_ok
    end

    it "reports a product without any price" do
      product("REF1")

      expect(finding("Chaque produit a au moins un tarif")).to have_attributes(records: ["REF1"])
    end

    it "reports a price that is not positive" do
      price(product("REF1"), "DEPC", "0")

      expect(finding("Tous les tarifs")).to have_attributes(records: ["REF1 DEPC"])
    end
  end

  describe "values written in the database" do
    it "reports a VAT rate that does not exist in France" do
      product("REF1", vat_rate: BigDecimal("19.6"))

      expect(finding("Tous les taux de TVA")).to have_attributes(records: ["REF1"])
    end

    # La base peut avoir été alimentée autrement que par l'import : le contrôle ne fait pas confiance
    # aux validations du modèle, il regarde les valeurs.
    it "reports a value outside the Baqio vocabulary" do
      product("REF1").update_column(:color, "vert")

      expect(finding("Les produits n'emploient")).to have_attributes(records: ["REF1"])
    end

    it "reports a country that is not an ISO code" do
      customer("C1", country_code: "XX")

      expect(finding("Les pays sont")).to have_attributes(records: ["C1"])
    end

    it "accepts a customer without any country" do
      customer("C1")

      expect(finding("Les pays sont")).to be_ok
    end
  end

  describe "price grids" do
    it "names every customer whose grid has no price at all" do
      price(product("REF1"), "DEPC", "10.00")
      customer("C1", price_grid_code: "GDCPT")

      expect(finding("Chaque grille tarifaire utilisée")).to have_attributes(records: ["C1 (GDCPT)"])
    end

    it "reports a grid no customer uses" do
      price(product("REF1"), "SALON", "10.00")

      expect(finding("Chaque grille tarifaire est utilisée")).to have_attributes(records: ["SALON"])
    end

    it "accepts a customer whose grid has prices" do
      price(product("REF1"), "DEPC", "10.00")
      customer("C1", price_grid_code: "DEPC")

      expect(finding("Chaque grille tarifaire utilisée")).to be_ok
    end
  end

  describe "grids that must carry the same prices" do
    let(:grids) { [["EXPO", "DEPC"]] }

    it "accepts prices that differ by no more than a cent" do
      vin = product("REF1")
      price(vin, "EXPO", "10.00")
      price(vin, "DEPC", "10.01")

      expect(finding("Les grilles", equal_price_grids: grids)).to be_ok
    end

    it "reports prices that differ" do
      vin = product("REF1")
      price(vin, "EXPO", "10.00")
      price(vin, "DEPC", "12.00")

      expect(finding("Les grilles", equal_price_grids: grids)).to have_attributes(records: ["REF1"])
    end

    it "ignores a product that has only one of the two grids" do
      price(product("REF1"), "EXPO", "10.00")

      expect(finding("Les grilles", equal_price_grids: grids)).to be_ok
    end

    it "checks nothing when no grids are declared equal" do
      expect(described_class.new.call.map { |candidate| candidate.label }).to all(satisfy { |label| !label.start_with?("Les grilles") })
    end
  end

  describe "#to_s" do
    it "tells what was checked, and what is in the database" do
      price(product("REF1"), "DEPC", "10.00")
      customer("C1", price_grid_code: "DEPC")

      expect(described_class.new.to_s).to start_with("Contrôles après reprise — 1 clients, 1 produits, 1 tarifs en base")
      expect(described_class.new.to_s).to include("OK     Chaque produit a au moins un tarif")
    end

    it "names the records in error" do
      product("REF1")

      expect(described_class.new.to_s).to include("ÉCART  Chaque produit a au moins un tarif : 1 (REF1)")
    end
  end
end
