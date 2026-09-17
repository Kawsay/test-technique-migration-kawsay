class Importer::Cavegest::CustomersLayout < Importer::Layout::Base
  COLUMNS = [
    [0,  :reference,             "Code"],
    [1,  :last_name,             "Nom"],
    [2,  :first_name,            "Prénom"],
    [3,  :company_name,          "Libellé"],
    [4,  :address1,              "Adresse"],
    [5,  :zip,                   "Code postal"],
    [6,  :city,                  "Ville"],
    [7,  :country,               "Pays"],
    [8,  :email,                 "EMail"],
    [9,  :phone,                 "Téléphone 1"],
    [10, :mobile,                "Téléphone 2"],
    [11, :shipping_last_name,    "Nom"],
    [12, :shipping_first_name,   "Prénom"],
    [13, :shipping_company_name, "Libellé"],
    [14, :shipping_address1,     "Adresse"],
    [15, :shipping_zip,          "Code postal"],
    [16, :shipping_city,         "Ville"],
    [17, :shipping_country,      "Pays"],
    [18, :shipping_phone,        "Téléphone 1"],
    [19, :kind_code,             "Code famille client"],
    [20, :kind_label,            "Libellé famille client"],
    [21, :price_grid_code,       "Code categ tarif"],
    [22, :price_grid_label,      "Libellé categ tarif"],
    [23, :vat_number,            "Numéro de TVA"],
    [24, :excise_number,         "Numéro d Accise"],
    [25, :creation_date,         "Date de création"],
    [26, :unusable,              "Inutilisable"],
  ].freeze

  TOTAL_MARKER      = "TOTAL".freeze
  EMPTY_MARKERS     = ["N/C"].freeze      # valeurs signifiant « non communiqué »
  DATE_FORMAT       = "%d/%m/%Y".freeze   # dates saisies en texte
  FLAG_TRUE_VALUES  = [1, "1"].freeze     # colonne « Inutilisable »
  FLAG_FALSE_VALUES = [0, "0"].freeze
  DEFAULT_COUNTRY   = "FR".freeze         # pays des téléphones écrits sans indicatif

  private

  def columns
    COLUMNS
  end

  def skipped_row?(row)
    row.values.first == TOTAL_MARKER
  end
end
