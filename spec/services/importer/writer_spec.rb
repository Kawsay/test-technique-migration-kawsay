require "spec_helper"

RSpec.describe Importer::Writer do
  let(:writer) { described_class.new(model: Customer, key: [:reference], columns: %i[reference company_name city]) }

  it "creates the records, and reports how many" do
    bilan = writer.call([{ reference: "C1", city: "Lyon" }, { reference: "C2", city: "Nantes" }])

    expect(Customer.pluck(:reference, :city)).to contain_exactly(["C1", "Lyon"], ["C2", "Nantes"])
    expect(bilan).to have_attributes(accepted: 2, created: 2, updated: 0, unchanged: 0)
  end

  it "writes nothing the second time" do
    rows = [{ reference: "C1", city: "Lyon" }]
    writer.call(rows)
    written_at = Customer.pluck(:updated_at)

    expect(writer.call(rows)).to have_attributes(accepted: 1, created: 0, updated: 0, unchanged: 1)
    expect(Customer.pluck(:updated_at)).to eq(written_at)
  end

  it "updates a record whose values changed" do
    writer.call([{ reference: "C1", city: "Lyon" }])

    expect(writer.call([{ reference: "C1", city: "Nantes" }])).to have_attributes(created: 0, updated: 1, unchanged: 0)
    expect(Customer.find_by(reference: "C1").city).to eq("Nantes")
  end

  # Une valeur que le fichier ne porte plus ne doit pas rester en base.
  it "clears the columns a record no longer carries" do
    writer.call([{ reference: "C1", company_name: "Cave Dupont", city: "Lyon" }])
    writer.call([{ reference: "C1", city: "Lyon" }])

    expect(Customer.find_by(reference: "C1").company_name).to be_nil
  end

  it "does not touch the columns it does not write" do
    Customer.create!(reference: "C1", company_name: "Cave Dupont", email: "contact@dupont.fr")
    writer.call([{ reference: "C1", company_name: "Cave Dupont", city: "Nantes" }])

    expect(Customer.find_by(reference: "C1").email).to eq("contact@dupont.fr")
  end

  it "writes nothing when there is no record" do
    expect(writer.call([])).to have_attributes(accepted: 0, created: 0, updated: 0, unchanged: 0)
  end

  describe "with a key of several columns" do
    let(:product) { Product.create!(reference: "REF1", name: "Vin rouge") }
    let(:writer)  { described_class.new(model: ProductPrice, key: %i[product_id grid_code], columns: %i[product_id grid_code amount_ht]) }

    it "tells records apart by all the columns of the key" do
      writer.call([{ product_id: product.id, grid_code: "DEPC", amount_ht: BigDecimal("10") }])

      bilan = writer.call([{ product_id: product.id, grid_code: "DEPC", amount_ht: BigDecimal("10") },
                           { product_id: product.id, grid_code: "CHR", amount_ht: BigDecimal("9") }])

      expect(bilan).to have_attributes(created: 1, updated: 0, unchanged: 1)
      expect(ProductPrice.pluck(:grid_code, :amount_ht)).to contain_exactly(["DEPC", BigDecimal("10")], ["CHR", BigDecimal("9")])
    end
  end
end
