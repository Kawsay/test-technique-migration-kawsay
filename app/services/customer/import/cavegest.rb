class Customer::Import::Cavegest < Importer::Base
  N = Importer::Normalization

  KINDS = { "C" => "customer", "F" => "supplier", "P" => "prospect" }.freeze

  def call
    imported = 0

    sheet.parse(headers: true).drop(1).each do |row|
      Customer.create!(
        reference:         N.text(row["Code"]),
        company_name:      N.text(row["Libellé"]),
        first_name:        N.text(row["Prénom"]),
        last_name:         N.text(row["Nom"]),
        address1:          N.text(row["Adresse"]),
        city:              N.text(row["Ville"]),
        zip:               N.zip(row["Code postal"]),
        country_code:      row["Pays"],
        phone:             row["Téléphone 1"].to_s,
        mobile:            row["Téléphone 2"].to_s,
        email:             row["EMail"].to_s,
        kind:              KINDS[N.text(row["Code famille client"])],
        customer_category: N.text(row["Libellé famille client"]),
        price_grid_code:   N.text(row["Code categ tarif"]),
        vat_number:        N.text(row["Numéro de TVA"]),
        excise_number:     N.text(row["Numéro d Accise"])
      )

      imported += 1
    end

    puts "#{imported} clients importés"
  end

  private

  def sheet
    @sheet ||= Roo::Excelx.new(path).sheet(0)
  end
end
