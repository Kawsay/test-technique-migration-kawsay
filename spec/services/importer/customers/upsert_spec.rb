require "spec_helper"

RSpec.describe Importer::Customers::Upsert do
  let(:report) { MigrationReport.new }
  let(:source) { "clients.xlsx" }

  # Un client préparé par Importer::Customers::Prepare, prêt à être écrit.
  def accepted(line, attributes)
    defaults = { reference: "C1", company_name: "Cave Dupont", kind: "customer", active: true, use_billing_address: true }
    record   = Importer::Layout::Base::Record.new(line: line, cells: { reference: attributes[:reference] })

    Importer::Customers::Prepare::Accepted.new(record: record, attributes: defaults.merge(attributes))
  end

  def upsert(accepted_customers)
    described_class.new(accepted: accepted_customers, source: source, report: report).call
  end

  def tally = report.tallies[[source, :customers]]

  def issue(code)
    report.issues.select { |candidate| candidate.code == code }
  end

  it "creates the customers with their attributes" do
    upsert([accepted(2, reference: "C1", city: "Lyon"), accepted(3, reference: "C2", city: "Nantes")])

    expect(Customer.pluck(:reference, :city)).to contain_exactly(["C1", "Lyon"], ["C2", "Nantes"])
  end

  it "reports how many customers were created" do
    upsert([accepted(2, reference: "C1")])

    expect(tally).to have_attributes(accepted: 1, created: 1, updated: 0, unchanged: 0)
  end

  describe "replaying the same file" do
    it "writes nothing the second time" do
      customers = [accepted(2, reference: "C1", city: "Lyon"), accepted(3, reference: "C2", city: "Nantes")]
      upsert(customers)
      written_at = Customer.pluck(:reference, :updated_at).to_h

      second_report = MigrationReport.new
      described_class.new(accepted: customers, source: source, report: second_report).call

      expect(Customer.count).to eq(2)
      expect(Customer.pluck(:reference, :updated_at).to_h).to eq(written_at)
      expect(second_report.tallies[[source, :customers]]).to have_attributes(accepted: 2, created: 0, updated: 0, unchanged: 2)
    end

    it "updates a customer whose values changed" do
      upsert([accepted(2, reference: "C1", city: "Lyon")])

      second_report = MigrationReport.new
      described_class.new(accepted: [accepted(2, reference: "C1", city: "Nantes")], source: source, report: second_report).call

      expect(Customer.find_by(reference: "C1").city).to eq("Nantes")
      expect(second_report.tallies[[source, :customers]]).to have_attributes(accepted: 1, created: 0, updated: 1, unchanged: 0)
    end

    # Un client qui n'a plus d'adresse de livraison ne doit pas garder l'ancienne.
    it "clears the columns a row no longer carries" do
      upsert([accepted(2, reference: "C1", shipping_city: "Narbonne", use_billing_address: false)])

      described_class.new(accepted: [accepted(2, reference: "C1", use_billing_address: true)], source: source,
                          report: MigrationReport.new).call

      expect(Customer.find_by(reference: "C1")).to have_attributes(shipping_city: nil, use_billing_address: true)
    end
  end

  describe "duplicated references" do
    it "imports no version of a reference read twice, and reports every row" do
      upsert([accepted(2, reference: "C1"), accepted(3, reference: "C1"), accepted(4, reference: "C2")])

      expect(Customer.pluck(:reference)).to eq(["C2"])
      expect(issue(:duplicate_identical).map { |candidate| [candidate.level, candidate.line, candidate.value] })
        .to eq([[:rejected, 2, "2, 3"], [:rejected, 3, "2, 3"]])
    end

    it "distinguishes rows that differ from one another" do
      upsert([accepted(2, reference: "C1", city: "Lyon"), accepted(3, reference: "C1", city: "Nantes")])

      expect(Customer.count).to eq(0)
      expect(issue(:duplicate_conflict).map { |candidate| candidate.line }).to eq([2, 3])
    end

    it "does not count the rejected rows as accepted" do
      upsert([accepted(2, reference: "C1"), accepted(3, reference: "C1"), accepted(4, reference: "C2")])

      expect(tally).to have_attributes(accepted: 1, created: 1, updated: 0, unchanged: 0)
    end
  end

  it "writes nothing when there is no customer to import" do
    upsert([])

    expect(Customer.count).to eq(0)
    expect(tally).to have_attributes(accepted: 0, created: 0, updated: 0, unchanged: 0)
  end

  describe "with the client's customers export" do
    before(:all) do
      Customer.delete_all
      report   = MigrationReport.new
      adapter  = Importer::Adapter::Xlsx.new(data_path("export_clients_cavegest.xlsx"), sheet: "Feuil1")
      accepted = Importer::Customers::Prepare.new(adapter: adapter, layout_class: Importer::Cavegest::CustomersLayout,
                                                  report: report).call

      @first_report = MigrationReport.new
      described_class.new(accepted: accepted, source: "export_clients_cavegest.xlsx", report: @first_report).call

      @second_report = MigrationReport.new
      described_class.new(accepted: accepted, source: "export_clients_cavegest.xlsx", report: @second_report).call
    end

    after(:all) { Customer.delete_all }

    # 4 994 lignes retenues, dont 6 portant l'une des 3 références lues deux fois.
    it "imports every customer but those whose reference is read twice" do
      expect(Customer.count).to eq(4988)
      expect(@first_report.tallies[["export_clients_cavegest.xlsx", :customers]])
        .to have_attributes(accepted: 4988, created: 4988, updated: 0, unchanged: 0)
    end

    it "reports the rows of the duplicated references" do
      expect(@first_report.by_level(:rejected).map { |candidate| candidate.entity })
        .to contain_exactly("Client T00101", "Client T00101", "Client T01501", "Client T01501",
                            "Client T03211", "Client T03211")
    end

    it "writes nothing when replayed" do
      expect(@second_report.tallies[["export_clients_cavegest.xlsx", :customers]])
        .to have_attributes(accepted: 4988, created: 0, updated: 0, unchanged: 4988)
    end
  end
end
