require "spec_helper"

RSpec.describe Importer::ProductPrices::Contract do
  let(:valid_attributes) { { reference: "REF1", name: "Vin rouge", vat_rate: BigDecimal("20") } }

  def codes(attributes)
    described_class.new.call(attributes).errors.map { |error| error.meta[:code] }
  end

  it "accepts a product with a reference, a name and a VAT rate" do
    expect(codes(valid_attributes)).to be_empty
  end

  { reference: :reference_missing, name: :name_missing, vat_rate: :vat_rate_missing }.each do |attribute, code|
    it "rejects a product without #{attribute}" do
      expect(codes(valid_attributes.merge(attribute => nil))).to eq([code])
    end
  end
end
