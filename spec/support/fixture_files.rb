require "tmpdir"
require "caxlsx"

module FixtureFiles
  TARIFFS_HEADER = "Ref;Désignation;Contenant;Couleur;TVA;DEPC;CHR;EXPO;PART;SALON;Stock".freeze

  CUSTOMER_COLUMNS = %i[
    reference last_name first_name company_name address1 zip city country email phone mobile
    shipping_last_name shipping_first_name shipping_company_name shipping_address1
    shipping_zip shipping_city shipping_country shipping_phone
    kind_code kind_label price_grid_code price_grid_label vat_number excise_number
    creation_date unusable
  ].freeze

  CUSTOMER_HEADERS = [
    "Code", "Nom", "Prénom", "Libellé", "Adresse", "Code postal", "Ville", "Pays", "EMail",
    "Téléphone 1", "Téléphone 2", "Nom", "Prénom", "Libellé", "Adresse", "Code postal", "Ville",
    "Pays", "Téléphone 1", "Code famille client", "Libellé famille client", "Code categ tarif",
    "Libellé categ tarif", "Numéro de TVA", "Numéro d Accise", "Date de création", "Inutilisable"
  ].freeze

  DEFAULT_CUSTOMER = {
    reference: "T90001", last_name: "MERCIER", first_name: "Marc", company_name: "LE VERRE GALANT",
    address1: "1 avenue de la Gare", zip: 69002, city: "Lyon", country: "France",
    kind_code: "C", kind_label: "Client France", price_grid_code: "DEPC", unusable: 0,
    # Le code hérité lit « Nom », « Prénom », « Libellé » dans le bloc livraison (en-têtes écrasés) :
    # on les recopie par défaut pour isoler chaque défaut des autres.
    shipping_last_name: "MERCIER", shipping_first_name: "Marc", shipping_company_name: "LE VERRE GALANT"
  }.freeze

  # CSV au format « simplifié » (UTF-8, en-tête en ligne 1, point décimal) sur lequel le code
  # hérité fonctionne : isole chaque défaut de ceux d'encodage, de préambule et de virgule.
  def simplified_tariffs_csv(*lines)
    path = File.join(Dir.mktmpdir, "tarifs.csv")
    File.write(path, [TARIFFS_HEADER, *lines].join("\r\n") + "\r\n")
    path
  end

  # Même structure que l'export réel : 27 colonnes, en-têtes dupliqués, nombres en cellules numériques.
  def customers_xlsx(*customers)
    path = File.join(Dir.mktmpdir, "clients.xlsx")
    Axlsx::Package.new do |package|
      package.workbook.add_worksheet(name: "Feuil1") do |sheet|
        sheet.add_row CUSTOMER_HEADERS
        customers.each do |overrides|
          values = CUSTOMER_COLUMNS.map { DEFAULT_CUSTOMER.merge(overrides)[_1] }
          sheet.add_row values, types: values.map { _1.is_a?(Integer) ? :integer : :string }
        end
      end
      package.serialize(path)
    end
    path
  end
end

RSpec.configure { |config| config.include FixtureFiles }
