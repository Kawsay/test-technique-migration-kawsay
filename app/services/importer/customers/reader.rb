# Lit les cellules d'une ligne de client avec les parsers, et retient les événements rencontrés.
class Importer::Customers::Reader
  Notice = Data.define(:level, :code, :field, :raw, :value)

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

  attr_reader :notices

  # record        - Importer::Layout::Base::Record à lire.
  # layout_class  - disposition de l'export, qui déclare les conventions de saisie du logiciel.
  # country_codes - Hash des codes pays déjà lus (voir Importer::Customers::Prepare#country_codes), partagé
  #                 entre les lignes : y lire une valeur brute inconnue la fait lire par le parser.
  def initialize(record:, layout_class:, country_codes:)
    @record        = record
    @layout_class  = layout_class
    @country_codes = country_codes
    @notices       = []
  end

  def text(field)
    read(field, Importer::Parsers.text(cell(field)))
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

  def date(field)
    read(field, Importer::Parsers.date(cell(field), format: @layout_class::DATE_FORMAT))
  end

  def flag(field)
    read(field, Importer::Parsers.flag(cell(field),
                                       true_values: @layout_class::FLAG_TRUE_VALUES,
                                       false_values: @layout_class::FLAG_FALSE_VALUES))
  end

  # Pays absent : pays par défaut du logiciel source, signalé comme correction.
  def country_code(field)
    return read(field, @country_codes[cell(field)]) unless cell(field).nil?

    default = @layout_class::DEFAULT_COUNTRY
    note(:country_defaulted, field: field, value: default)
    default
  end

  # Valeur brute d'un champ, telle que saisie par le client.
  def raw(field)
    @record.cells[CELLS_BY_FIELD.fetch(field, field)]
  end

  def note(code, field:, value:)
    @notices << Notice.new(level: LEVELS_BY_CODE.fetch(code), code: code, field: field, raw: raw(field), value: value)
  end

  private

  # Valeur normalisée d'un champ : les marqueurs de valeur absente du logiciel source sont des cellules vides.
  def cell(field)
    value = raw(field)

    @layout_class::EMPTY_MARKERS.include?(value) ? nil : value
  end

  # Une valeur illisible vide le champ ; une correction ou un doute est noté.
  def read(field, result)
    if result.failure?
      note(result.failure, field: field, value: nil)
      return nil
    end

    parsed = result.value!
    note(parsed.notice, field: field, value: parsed.value) if parsed.notice

    parsed.value
  end
end
