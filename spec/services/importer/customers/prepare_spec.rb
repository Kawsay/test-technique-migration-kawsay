require "spec_helper"

RSpec.describe Importer::Customers::Prepare do
  let(:layout_class) { Importer::Cavegest::CustomersLayout }
  let(:header)       { layout_class::COLUMNS.map { |_position, _field, name| name } }
  let(:report)       { MigrationReport.new }

  # Valeurs d'une ligne de l'export clients CaveGest : un client valide, modifié par `cells`.
  def customer_row(cells = {})
    defaults = { reference: "C1", company_name: "Cave Dupont", country: "France", kind_code: "C", unusable: 0 }
    values   = Array.new(layout_class::COLUMNS.size)

    layout_class::COLUMNS.each do |position, field, _name|
      values[position] = defaults.merge(cells)[field]
    end

    values
  end

  def import(lines, header_row: header)
    adapter = double("adapter", rows: rows([header_row] + lines), file_name: "clients.xlsx")
    described_class.new(adapter: adapter, layout_class: layout_class, report: report).call
  end

  def attributes_of(cells)
    import([customer_row(cells)]).first.attributes
  end

  def issue(code)
    report.issues.find { |candidate| candidate.code == code }
  end

  describe "accepted customers" do
    it "returns the attributes of the customer, with its original record" do
      accepted = import([customer_row(reference: "C1", company_name: "Cave Dupont", city: "Lyon")]).first

      expect(accepted.record.line).to eq(2)
      expect(accepted.attributes).to include(reference: "C1", company_name: "Cave Dupont", city: "Lyon",
                                             kind: "customer", country_code: "FR", active: true)
    end

    it "keeps the file order" do
      accepted = import([customer_row(reference: "C1"), customer_row(reference: "C2")])

      expect(accepted.map { |candidate| candidate.attributes[:reference] }).to eq(["C1", "C2"])
    end

    it "does not write anything in the database" do
      expect { import([customer_row]) }.not_to change(Customer, :count)
    end

    it "reports nothing for a customer read as is" do
      import([customer_row])

      expect(report.issues).to be_empty
    end
  end

  describe "conventions of the source software" do
    it "reads an empty marker as an empty value, without reporting it" do
      expect(attributes_of(phone: "N/C")).to include(phone: nil)
      expect(report.issues).to be_empty
    end

    it "reads dates in DD/MM/YYYY format" do
      expect(attributes_of(creation_date: "01/02/2020")).to include(creation_date: Date.new(2020, 2, 1))
    end

    it "imports a customer flagged as unusable as inactive" do
      expect(attributes_of(unusable: 1)).to include(active: false)
    end

    it "maps the family code to the kind of customer" do
      expect(attributes_of(kind_code: "F")).to include(kind: "supplier")
    end
  end

  describe "repaired values" do
    it "reports a restored value with its line, field, raw and retained values, and the original row" do
      attributes = attributes_of(reference: "C1", zip: 1000)

      expect(attributes).to include(zip: "01000")
      expect(issue(:zip_padded)).to have_attributes(
        level: :repaired, source: "clients.xlsx", line: 2, entity: "Client C1",
        field: :zip, raw: 1000, value: "01000", cells: include(reference: "C1", zip: 1000)
      )
    end

    it "uses the default country of the software when the country is missing" do
      expect(attributes_of(country: nil)).to include(country_code: "FR")
      expect(issue(:country_defaulted)).to have_attributes(level: :repaired, field: :country_code, raw: nil, value: "FR")
    end

    it "imports a reseller as a customer, and reports the decision" do
      expect(attributes_of(kind_code: "R")).to include(kind: "customer")
      expect(issue(:kind_reseller_as_customer)).to have_attributes(level: :repaired, field: :kind, raw: "R", value: "customer")
    end
  end

  describe "doubtful values" do
    it "empties an unreadable field and reports its raw value" do
      expect(attributes_of(email: "jean@")).to include(email: nil)
      expect(issue(:email_invalid)).to have_attributes(level: :suspect, field: :email, raw: "jean@", value: nil)
    end

    it "empties an unknown country and keeps the postal code as is" do
      expect(attributes_of(country: "Atlantide", zip: 1000)).to include(country_code: nil, zip: "1000")
      expect(issue(:country_unknown)).to have_attributes(level: :suspect, field: :country_code, raw: "Atlantide")
    end

    it "keeps a phone number outside the assigned ranges, and reports it" do
      expect(attributes_of(phone: "06 90 12 34 56")).to include(phone: "+33690123456")
      expect(issue(:phone_unassigned)).to have_attributes(level: :suspect, field: :phone, value: "+33690123456")
    end
  end

  describe "rejected rows" do
    it "rejects a customer without company name, first name nor last name" do
      accepted = import([customer_row(reference: "C1", company_name: nil)])

      expect(accepted).to be_empty
      expect(issue(:name_missing)).to have_attributes(
        level: :rejected, line: 2, entity: "Client C1", field: nil, cells: include(reference: "C1")
      )
    end

    it "rejects a customer of unknown family code, with the raw code" do
      expect(import([customer_row(kind_code: "X")])).to be_empty
      expect(issue(:kind_unknown)).to have_attributes(level: :rejected, field: :kind, raw: "X")
    end

    it "rejects a customer without reference" do
      expect(import([customer_row(reference: nil)])).to be_empty
      expect(issue(:reference_missing)).to have_attributes(level: :rejected, entity: nil, field: :reference)
    end

    # Le client doit corriger la raison du rejet ; les autres anomalies de la ligne seraient du bruit.
    it "reports only the reasons of the rejection" do
      import([customer_row(company_name: nil, email: "jean@", zip: 1000)])

      expect(report.issues.map { |candidate| candidate.code }).to eq([:name_missing])
    end

    it "keeps importing the following rows" do
      accepted = import([customer_row(reference: "C1", company_name: nil), customer_row(reference: "C2")])

      expect(accepted.map { |candidate| candidate.attributes[:reference] }).to eq(["C2"])
    end
  end

  describe "shipping address" do
    let(:billing) { { last_name: "Dupont", address1: "1 rue des Vignes", zip: 69001, city: "Lyon" } }

    it "uses the billing address when the shipping block is empty" do
      attributes = attributes_of(billing)

      expect(attributes).to include(use_billing_address: true)
      expect(attributes.keys).not_to include(:shipping_address1)
    end

    it "uses the billing address when the shipping block repeats it" do
      shipping = { shipping_last_name: "Dupont", shipping_company_name: "Cave Dupont", shipping_address1: "1 rue des Vignes",
                   shipping_zip: 69001, shipping_city: "Lyon", shipping_country: "France" }

      attributes = attributes_of(billing.merge(shipping))

      expect(attributes).to include(use_billing_address: true)
      expect(attributes.keys).not_to include(:shipping_address1)
    end

    it "stores a shipping address that differs from the billing one" do
      shipping = { shipping_last_name: "Dupont", shipping_address1: "2 rue du Port", shipping_zip: 13002, shipping_city: "Marseille",
                   shipping_country: "France" }

      expect(attributes_of(billing.merge(shipping))).to include(
        use_billing_address: false, shipping_address1: "2 rue du Port", shipping_zip: "13002", shipping_city: "Marseille",
        shipping_country_code: "FR"
      )
    end

    # Le pays de facturation ne convient pas : un client belge peut se faire livrer en France.
    it "uses the default country of the software when the shipping country is missing" do
      attributes = attributes_of(country: "Belgique", zip: 5000, shipping_address1: "2 rue du Port", shipping_zip: 13002)

      expect(attributes).to include(country_code: "BE", shipping_country_code: "FR", shipping_zip: "13002")
    end

    it "does not report anomalies of a shipping address that is not stored" do
      shipping = { shipping_company_name: "Cave Dupont", shipping_country: "France", shipping_phone: 123456789 }

      attributes = attributes_of(phone: 123456789, **shipping)

      expect(attributes).to include(use_billing_address: true)
      expect(report.issues.map { |candidate| candidate.field }).to eq([:phone])
    end
    end

  describe "client file anomalies" do
    it "rejects the whole file when its header differs, and reports why" do
      unexpected_header = ["Autre"] + header.drop(1)

      expect(import([customer_row], header_row: unexpected_header)).to be_empty
      expect(issue(:file_rejected)).to have_attributes(
        level: :rejected, source: "clients.xlsx", line: nil, value: 'unexpected header (column 1: expected "Code", found "Autre")'
      )
    end

    it "reports an empty additional column as information" do
      import([customer_row], header_row: header + ["Remarque"])

      expect(issue(:column_ignored)).to have_attributes(level: :info, entity: "Colonne 28", raw: "Remarque", value: 0)
    end

    it "reports a filled additional column as doubtful, since its values are not imported" do
      import([customer_row + ["Livrer le matin"]], header_row: header + ["Remarque"])

      expect(issue(:column_ignored)).to have_attributes(level: :suspect, raw: "Remarque", value: 1)
    end
    end

  describe "technical problems" do
    it "does not turn an unexpected error into a client file anomaly" do
      adapter = double("adapter", file_name: "clients.xlsx")
      allow(adapter).to receive(:rows).and_raise(RuntimeError, "disk failure")

      expect { described_class.new(adapter: adapter, layout_class: layout_class, report: report).call }
        .to raise_error(RuntimeError, "disk failure")
    end
  end

  describe "with the client's customers export" do
    before(:all) do
      @report   = MigrationReport.new
      adapter   = Importer::Adapter::Xlsx.new(data_path("export_clients_cavegest.xlsx"), sheet: "Feuil1")
      @accepted = described_class.new(adapter: adapter, layout_class: Importer::Cavegest::CustomersLayout, report: @report).call
    end

    # 4 997 lignes de clients, dont 3 sans raison sociale, nom ni prénom.
    it "accepts every customer but those without name" do
      expect(@accepted.size).to eq(4994)
      expect(@report.by_level(:rejected).map { |rejection| rejection.entity })
        .to contain_exactly("Client T00078", "Client T01803", "Client T04000")
    end

    it "imports the customers flagged as unusable as inactive" do
      expect(@accepted.count { |candidate| candidate.attributes[:active] == false }).to eq(340)
    end

    it "reports the corrections and the doubtful values found in the export" do
      counts = @report.issues.group_by { |candidate| [candidate.level, candidate.code] }.transform_values(&:size)

      expect(counts).to eq(
        [:repaired, :zip_padded]                  => 1646,
        [:repaired, :phone_leading_zero_restored] => 4530,
        [:repaired, :country_defaulted]           => 1128,
        [:repaired, :kind_reseller_as_customer]   => 981,
        [:suspect,  :email_invalid]               => 179,
        [:suspect,  :phone_unassigned]            => 159,
        [:rejected, :name_missing]                => 3
      )
    end
  end

  it "carries every attribute it is responsible for" do
    shipping   = { shipping_address1: "2 rue du Port", shipping_zip: 13002, shipping_country: "France" }
    attributes = attributes_of(shipping)

    expect(attributes.keys).to match_array(Importer::Customers::ATTRIBUTES)
  end
end
