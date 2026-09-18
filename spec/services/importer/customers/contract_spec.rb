require "spec_helper"

RSpec.describe Importer::Customers::Contract do
  let(:valid_attributes) do
    { reference: "C1", kind: "customer", company_name: "Cave Dupont", first_name: nil, last_name: nil }
  end

  def codes(attributes)
    described_class.new.call(attributes).errors.map { |error| error.meta[:code] }
  end

  it "accepts a customer with a reference, a known kind and a name" do
    expect(codes(valid_attributes)).to be_empty
  end

  it "accepts a customer identified only by a last name" do
    expect(codes(valid_attributes.merge(company_name: nil, last_name: "Dupont"))).to be_empty
  end

  it "rejects a customer without reference" do
    expect(codes(valid_attributes.merge(reference: nil))).to eq([:reference_missing])
  end

  it "rejects a customer of unknown kind" do
    expect(codes(valid_attributes.merge(kind: nil))).to eq([:kind_unknown])
  end

  it "rejects a customer without company name, first name nor last name" do
    expect(codes(valid_attributes.merge(company_name: nil))).to eq([:name_missing])
  end

  it "reports every broken rule" do
    expect(codes(valid_attributes.merge(reference: nil, kind: nil, company_name: nil)))
      .to contain_exactly(:reference_missing, :kind_unknown, :name_missing)
  end
end
