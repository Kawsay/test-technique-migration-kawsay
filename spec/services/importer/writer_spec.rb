require "spec_helper"

RSpec.describe Importer::Writer do
  let(:writer) { described_class.new(model: Customer, key: [:reference], columns: %i[reference company_name city]) }

  def customer(reference, city: "Lyon") = { reference: reference, company_name: "Cave Dupont", city: city }

  it "creates the records, and reports how many" do
    bilan = writer.call([customer("C1", city: "Lyon"), customer("C2", city: "Nantes")])

    expect(Customer.pluck(:reference, :city)).to contain_exactly(["C1", "Lyon"], ["C2", "Nantes"])
    expect(bilan).to have_attributes(accepted: 2, created: 2, updated: 0, unchanged: 0)
  end

  it "writes nothing the second time" do
    writer.call([customer("C1")])
    written_at = Customer.pluck(:updated_at)

    expect(writer.call([customer("C1")])).to have_attributes(accepted: 1, created: 0, updated: 0, unchanged: 1)
    expect(Customer.pluck(:updated_at)).to eq(written_at)
  end

  it "updates a record whose values changed" do
    writer.call([customer("C1", city: "Lyon")])

    expect(writer.call([customer("C1", city: "Nantes")])).to have_attributes(created: 0, updated: 1, unchanged: 0)
    expect(Customer.find_by(reference: "C1").city).to eq("Nantes")
  end

  # Une valeur que le fichier ne porte plus ne doit pas rester en base.
  it "clears the columns a record no longer carries" do
    writer.call([customer("C1", city: "Lyon")])
    writer.call([{ reference: "C1", company_name: "Cave Dupont" }])

    expect(Customer.find_by(reference: "C1").city).to be_nil
  end

  it "does not touch the columns it does not write" do
    Customer.create!(reference: "C1", company_name: "Cave Dupont", email: "contact@dupont.fr")
    writer.call([customer("C1")])

    expect(Customer.find_by(reference: "C1").email).to eq("contact@dupont.fr")
  end

  # Le contrat de l'import aurait dû rejeter la ligne : c'est une erreur de notre code, pas du fichier.
  it "refuses a record its model finds invalid, and writes none of the others" do
    rows = [customer("C1"), { reference: "C2" }]

    expect { writer.call(rows) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(Customer.count).to eq(0)
  end

  it "writes nothing when there is no record" do
    expect(writer.call([])).to have_attributes(accepted: 0, created: 0, updated: 0, unchanged: 0)
  end

  describe "with a key of several columns" do
    let(:product) { Product.create!(reference: "REF1", name: "Vin rouge") }
    let(:writer)  { described_class.new(model: ProductPrice, key: %i[product_id grid_code], columns: %i[product_id grid_code amount_ht]) }

    def price(grid_code, amount) = { product_id: product.id, grid_code: grid_code, amount_ht: BigDecimal(amount) }

    it "tells records apart by all the columns of the key" do
      writer.call([price("DEPC", "10")])

      bilan = writer.call([price("DEPC", "10"), price("CHR", "9")])

      expect(bilan).to have_attributes(created: 1, updated: 0, unchanged: 1)
      expect(ProductPrice.pluck(:grid_code, :amount_ht)).to contain_exactly(["DEPC", BigDecimal("10")], ["CHR", BigDecimal("9")])
    end
  end
end
