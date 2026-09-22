# Lit les cellules d'une ligne de client avec les parsers, et retient les événements rencontrés.
class Importer::Customers::Reader < Importer::Reader
  LEVELS_BY_CODE = {
    # Valeurs corrigées : le client valide la règle appliquée.
    zip_padded:                  :repaired,
    phone_leading_zero_restored: :repaired,
    country_defaulted:           :repaired,
    kind_reseller_as_customer:   :repaired,

    # Valeurs reprises telles quelles mais douteuses : le client vérifie.
    phone_unassigned:            :suspect,

    # Valeurs illisibles : le champ est vidé, le client corrige son fichier s'il y tient.
    zip_invalid:                 :suspect,
    country_unknown:             :suspect,
    phone_invalid:               :suspect,
    email_invalid:               :suspect,
    date_invalid:                :suspect,
    flag_invalid:                :suspect
  }.freeze

  # Champ du Customer => cellule d'où il est lu, quand leurs noms diffèrent.
  CELLS_BY_FIELD = {
    country_code:          :country,
    shipping_country_code: :shipping_country,
    kind:                  :kind_code,
    customer_category:     :kind_label,
    active:                :unusable
  }.freeze

  # country_codes - Hash des codes pays déjà lus (voir Importer::Customers::Prepare#country_codes), partagé
  #                 entre les lignes : y lire une valeur brute inconnue la fait lire par le parser.
  def initialize(record:, layout_class:, country_codes:)
    super(record: record, layout_class: layout_class)
    @country_codes = country_codes
  end

  def email(field)
    read(field, Importer::Parsers.email(cell(field)))
  end

  def zip(field, country_code)
    read(field, Importer::Parsers.zip(cell(field), country_code))
  end

  def phone(field)
    read(field, Importer::Parsers.phone(cell(field), default_country: @layout_class::DEFAULT_COUNTRY))
  end

  # Pays absent : pays par défaut du logiciel source, signalé comme correction.
  def country_code(field)
    return read(field, @country_codes[cell(field)]) unless cell(field).nil?

    default = @layout_class::DEFAULT_COUNTRY
    note(:country_defaulted, field: field, value: default)
    default
  end
end
