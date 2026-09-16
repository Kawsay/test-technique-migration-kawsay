require "spec_helper"

RSpec.describe Customer::Import::Cavegest do
  def import(path) = described_class.new(path).call

  before { described_class.new(data_path("export_clients_cavegest.xlsx")).call }

  it "keeps the leading zero of postal codes" do
    expect(Customer.find_by(reference: "T00022").zip).to eq("01000")
  end

  it "skips the totals row at the bottom of the file" do
    expect(Customer.where(reference: "TOTAL")).to be_empty
  end

  it "stores the shipping address when it differs from the billing one" do
    customer = Customer.find_by(reference: "T00013")

    expect(customer.zip).to eq("04000")
    expect(customer.shipping_zip).to eq("11100")
  end


  describe "with the client's actual file" do
    it "reads all 27 columns, including the duplicated billing / shipping headers" do
      sheet = Roo::Excelx.new(data_path("export_clients_cavegest.xlsx")).sheet("Feuil1")

      expect(sheet.parse(headers: true).drop(1).first.keys.size).to eq(27)
    end

    it "does not abort on the first row (family code 'R')" do
      expect { import(data_path("export_clients_cavegest.xlsx")) }.not_to raise_error
    end
  end

  describe "with an extract matching the export format" do
    it "imports a customer without a shipping address" do
      path = customers_xlsx({ shipping_last_name: nil, shipping_first_name: nil, shipping_company_name: nil })

      expect { import(path) }.to change(Customer, :count).by(1)
    end

    it "stores an ISO country code when the country is spelled out" do
      import(customers_xlsx({ shipping_country: "France" }))

      expect(Customer.last.country_code).to eq("FR")
    end

    it "reads the billing postal code, not the shipping one" do
      import(customers_xlsx({ zip: 69002, shipping_zip: 11100, shipping_city: "Narbonne" }))

      expect(Customer.last.zip).to eq("69002")
    end

    it "reads the billing last name, not the shipping one" do
      import(customers_xlsx({ last_name: "MERCIER", shipping_last_name: "DUPONT", shipping_zip: 11100 }))

      expect(Customer.last.last_name).to eq("MERCIER")
    end

    it "accepts resellers (family code 'R')" do
      path = customers_xlsx({ kind_code: "R", kind_label: "REVENDEUR" })

      expect { import(path) }.to change(Customer, :count).by(1)
      it "does not abort on the TOTAL row" do
        path = customers_xlsx({}, { reference: "TOTAL", last_name: nil, first_name: nil,
                                    company_name: "5000 tiers", kind_code: nil, zip: nil, unusable: nil })

        expect { import(path) }.not_to raise_error
      end

      it "does not abort on a duplicated reference" do
        path = customers_xlsx({ reference: "T00101" }, { reference: "T00101" })

        expect { import(path) }.not_to raise_error
      end

      it "restores the leading zero of a phone number read as a number" do
        # recopié en livraison : le code hérité lit « Téléphone 1 » dans ce bloc
        import(customers_xlsx({ phone: 574690103, shipping_phone: 574690103 }))

        expect(Customer.last.phone).to match(/\A(\+33|0)574690103\z/)
      end

      it "does not store an empty phone number as an empty string" do
        import(customers_xlsx({ mobile: nil }))

        expect(Customer.last.mobile).to be_nil
      end

      it "strips whitespace around the email" do
        import(customers_xlsx({ email: "  contact@le-verre-galant.fake  " }))

        expect(Customer.last.email).to eq("contact@le-verre-galant.fake")
      end

      it "does not store an invalid email" do
        import(customers_xlsx({ email: "paul@" }))

        expect(Customer.last.email).to be_nil
      end

      it "imports the creation date" do
        import(customers_xlsx({ creation_date: "22/07/2013" }))

        expect(Customer.last.creation_date).to eq(Date.new(2013, 7, 22))
      end

      it "imports a customer flagged 'Inutilisable' as inactive" do
        import(customers_xlsx({ unusable: 1 }))

        expect(Customer.last.active).to be(false)
      end

      it "stores the shipping address when it differs from the billing one" do
        import(customers_xlsx({ shipping_last_name: "MERCIER", shipping_address1: "5 rue des Vignes",
                                shipping_zip: 11100, shipping_city: "Narbonne" }))

        expect(Customer.last).to have_attributes(
          use_billing_address: false, shipping_address1: "5 rue des Vignes", shipping_zip: "11100"
        )
      end
    end
  end
end
