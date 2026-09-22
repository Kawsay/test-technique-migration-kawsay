require "spec_helper"

RSpec.describe Product do
  def product(attributes = {}) = described_class.new({ reference: "REF1", name: "Vin rouge" }.merge(attributes))

  describe "#total_volume_ml" do
    it "multiplies the volume of a unit by the number of units" do
      expect(product(units_per_container: 6, volume_ml: 750).total_volume_ml).to eq(4500)
    end

    it "is the volume of the unit for a single bottle" do
      expect(product(units_per_container: 1, volume_ml: 750).total_volume_ml).to eq(750)
    end

    it "is unknown when the volume of a unit is unknown" do
      expect(product(units_per_container: 6, volume_ml: nil).total_volume_ml).to be_nil
    end

    it "is unknown when the unit per container is unknown" do
      expect(product(units_per_container: nil, volume_ml: 750).total_volume_ml).to be_nil
    end
  end

  describe "vocabulary" do
    { color: "red", appellation: "aop", product_type: "still_wine", container_type: "case" }.each do |attribute, value|
      it "accepts #{attribute} #{value.inspect}" do
        expect(product(attribute => value)).to be_valid
      end

      it "rejects an unknown #{attribute}" do
        expect(product(attribute => "unknown")).not_to be_valid
      end

      it "accepts no #{attribute}" do
        expect(product(attribute => nil)).to be_valid
      end
    end

    it "rejects a container without any unit" do
      expect(product(units_per_container: 0)).not_to be_valid
    end
  end
end
