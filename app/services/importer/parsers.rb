# Transforment une valeur brute de cellule en valeur fiable.
#
# Chaque parser renvoie :
#   Success(Parsed(value))          valeur lue telle quelle (nil pour une cellule vide) ;
#   Success(Parsed(value, notice))  valeur lue, avec un événement à signaler (correction appliquée, doute) ;
#   Failure(:code)                  valeur illisible.
#
# Les règles appliquées sont génériques (normes, règles postales…) et ne dépendent d'aucun logiciel source.
# Les conventions de saisie propres à un logiciel (format de date, valeurs d'un indicateur, pays par défaut)
# sont passées en paramètres par l'appelant ; les marqueurs de valeur absente ("N/C"…) sont traités avant.
#
# Un parser ne lève jamais d'exception sur une valeur du client, et ne décide pas des conséquences
# (rejet de la ligne, champ vidé, niveau de gravité) : cela dépend du champ, c'est le rôle de l'importeur.
module Importer::Parsers
  extend ::Dry::Monads[:result]

  # value  - valeur retenue.
  # notice - Symbol identifiant l'événement à signaler, nil si aucun.
  Parsed = Data.define(:value, :notice) do
    def initialize(value:, notice: nil)
      super
    end
  end

  def self.text(raw)
    value = raw.to_s.strip
    return Success(Parsed.new(value: nil)) if value.empty?

    Success(Parsed.new(value: value))
  end

  # Terme d'un vocabulaire du logiciel d'origine, saisi librement (ex. « Client France », « CLIENT FRANCE ») :
  # mis en majuscules pour que la même catégorie ne se retrouve pas en base sous plusieurs orthographes.
  def self.label(raw)
    value = raw.to_s.strip.upcase
    return Success(Parsed.new(value: nil)) if value.empty?

    Success(Parsed.new(value: value))
  end

  # Identifiant administratif saisi librement (numéro de TVA, d'accise) : espaces et ponctuation retirés,
  # majuscules, pour que « FR 69 995954011 » et « FR69995954011 » soient la même valeur en base.
  # Sa validité n'est pas contrôlée : seule l'administration peut le dire.
  def self.identifier(raw)
    value = raw.to_s.upcase.delete("^A-Z0-9")
    return Success(Parsed.new(value: nil)) if value.empty?

    Success(Parsed.new(value: value))
  end

  # Excel stocke les codes postaux comme des nombres : le zéro initial des départements 01 à 09 est perdu.
  # Seules les règles française et belge sont connues ; pour un autre pays, la valeur est gardée telle quelle.
  #
  # Liste exhaustive des codes postaux ainsi que les regexs préconnisées par la BCE :
  #   https://www.ecb.europa.eu/stats/ecb_statistics/anacredit/questions/html/ecb.anaq.210430.0001.fr.html
  #
  # value.delete("0-9") retire tous les chiffres de 0 à 9 : s'il ne reste rien, la valeur n'est faite que de chiffres.
  def self.zip(raw, country_code)
    return Success(Parsed.new(value: nil)) if raw.nil?
    return Failure(:zip_invalid) unless raw.is_a?(String) || raw.is_a?(Integer)

    value = raw.to_s.strip
    return Success(Parsed.new(value: nil)) if value.empty?

    case country_code
    when "FR"
      return Failure(:zip_invalid) unless value.delete("0-9").empty?
      return Success(Parsed.new(value: value)) if value.length == 5
      return Success(Parsed.new(value: value.rjust(5, "0"), notice: :zip_padded)) if value.length == 4

      Failure(:zip_invalid)
    when "BE"
      return Success(Parsed.new(value: value)) if value.delete("0-9").empty? && value.length == 4

      Failure(:zip_invalid)
    else
      Success(Parsed.new(value: value))
    end
  end

  # Code pays ISO 3166-1 alpha-2 (ex. "FR"), à partir d'un code ("fr", "FR") ou d'un nom de pays,
  # dans l'une des langues connues de la gem countries ("France", "Allemagne", "Germany").
  def self.country_code(raw)
    text = raw.to_s.strip
    return Success(Parsed.new(value: nil)) if text.empty?

    country = ISO3166::Country[text.upcase] || ISO3166::Country.find_country_by_any_name(text)
    return Failure(:country_unknown) if country.nil?

    Success(Parsed.new(value: country.alpha2))
  end

  # Numéro de téléphone au format international E.164 (ex. "+33123456789").
  #
  # default_country - code ISO 3166-1 alpha-2 du pays des numéros écrits sans indicatif (ex. "FR").
  #
  # La validation s'appuie sur les plages de numéros attribuées (gem phonelib, données libphonenumber).
  # Un numéro de longueur correcte mais hors de ces plages est gardé et signalé : c'est le cas
  # des mobiles d'outre-mer (0690, 0694…) écrits au format national français, qui n'appartiennent pas à +33.
  #
  # Pour la France, un numéro saisi comme nombre dans Excel a perdu son zéro initial : il ne lui reste
  # que 9 chiffres. S'il est aussi hors des plages attribuées, seul :phone_unassigned est signalé.
  def self.phone(raw, default_country:)
    return Success(Parsed.new(value: nil)) if raw.nil?
    return Failure(:phone_invalid) unless raw.is_a?(String) || raw.is_a?(Integer)

    digits = raw.to_s.strip.delete(" .-")
    return Success(Parsed.new(value: nil)) if digits.empty?

    notice = nil

    if default_country == "FR" && digits.length == 9 && !digits.start_with?("0", "+")
      digits = "0#{digits}"
      notice = :phone_leading_zero_restored
    end

    phone = Phonelib.parse(digits, default_country)
    return Success(Parsed.new(value: phone.e164, notice: notice)) if phone.valid?
    return Success(Parsed.new(value: phone.e164, notice: :phone_unassigned)) if phone.possible?

    Failure(:phone_invalid)
  end

    # Adresse email à laquelle le client peut être contacté.
    #
    # Le format est vérifié par URI::MailTo::EMAIL_REGEXP (bibliothèque standard, norme HTML), qui refuse
    # notamment un domaine vide ou mal découpé ("jean@.fr", "jean@exemple..fr").
    # Cette norme accepte un domaine sans extension ("jean@exemple"), valable sur un réseau local
    # mais inutilisable pour joindre un client : le domaine doit donc se terminer par une extension
    # d'au moins deux lettres (".fr", ".com").
    def self.email(raw)
      value = raw.to_s.strip
      return Success(Parsed.new(value: nil)) if value.empty?
      return Failure(:email_invalid) unless value.match?(URI::MailTo::EMAIL_REGEXP)

      domain    = value.split("@").last
      extension = domain.split(".").last
      return Failure(:email_invalid) unless domain.include?(".") && extension.length >= 2

      Success(Parsed.new(value: value))
    end

  # Date, déjà lue comme telle par l'adaptateur, ou texte au format donné.
  #
  # format - format du texte, au sens de Date.strptime (ex. "%d/%m/%Y").
  #
  # Date.strptime est permissif : avec "%d/%m/%Y", "01/02/20" donne l'an 20 et "01/02/2020 abc" est accepté.
  # La date lue est donc réécrite au même format et doit redonner exactement le texte d'origine.
  def self.date(raw, format:)
    return Success(Parsed.new(value: nil)) if raw.nil?
    return Success(Parsed.new(value: raw)) if raw.instance_of?(Date)
    return Failure(:date_invalid) unless raw.is_a?(String)

    text = raw.strip
    return Success(Parsed.new(value: nil)) if text.empty?

    date = Date.strptime(text, format)
    return Failure(:date_invalid) unless date.strftime(format) == text

    Success(Parsed.new(value: date))
  rescue Date::Error
    Failure(:date_invalid)
  end

  # Indicateur oui / non.
  #
  # true_values, false_values - Array des valeurs brutes signifiant oui et non (ex. [1, "1"] et [0, "0"]).
  def self.flag(raw, true_values:, false_values:)
    return Success(Parsed.new(value: true)) if true_values.include?(raw)
    return Success(Parsed.new(value: false)) if false_values.include?(raw)

    Failure(:flag_invalid)
  end

  # Montant en euros (ex. "13,32", "  19,31 EUR", "13"), en BigDecimal : un montant n'est jamais un Float.
  #
  # Virgule ou point décimal ; un suffixe "EUR" ou "€" est retiré. Tout autre caractère (signe, exposant,
  # séparateur de milliers) rend le montant illisible plutôt que de risquer une lecture fausse.
  def self.money(raw)
    return Success(Parsed.new(value: nil)) if raw.nil?
    return Success(Parsed.new(value: BigDecimal(raw))) if raw.is_a?(Integer)
    return Failure(:amount_invalid) unless raw.is_a?(String)

    text = raw.strip.delete_suffix("EUR").delete_suffix("€").strip.tr(",", ".")
    return Success(Parsed.new(value: nil)) if text.empty?
    return Failure(:amount_invalid) unless decimal_number?(text)

    Success(Parsed.new(value: BigDecimal(text)))
  end

  # Taux de TVA applicables en France.
  FRENCH_VAT_RATES = [BigDecimal("20"), BigDecimal("10"), BigDecimal("5.5"), BigDecimal("2.1")].freeze

  # Taux de TVA en pourcentage (ex. "20", "20%", "5,50"), parmi les taux applicables en France.
  def self.vat_rate(raw)
    return Success(Parsed.new(value: nil)) if raw.nil?

    text = raw.to_s.strip.delete_suffix("%").strip.tr(",", ".")
    return Success(Parsed.new(value: nil)) if text.empty?
    return Failure(:vat_rate_invalid) unless decimal_number?(text)

    rate = BigDecimal(text)
    return Failure(:vat_rate_unknown) unless FRENCH_VAT_RATES.include?(rate)

    Success(Parsed.new(value: rate))
  end

  # Nombre entier (ex. un stock), éventuellement négatif.
  def self.integer(raw)
    return Success(Parsed.new(value: nil)) if raw.nil?
    return Success(Parsed.new(value: raw)) if raw.is_a?(Integer)
    return Failure(:integer_invalid) unless raw.is_a?(String)

    text = raw.strip
    return Success(Parsed.new(value: nil)) if text.empty?
    return Failure(:integer_invalid) unless text.delete_prefix("-").delete("0-9").empty? && text != "-"

    Success(Parsed.new(value: Integer(text, 10)))
  end

  # Terme d'un vocabulaire (ex. une couleur), sans tenir compte de la casse ni des espaces.
  #
  # terms   - Hash { terme du logiciel d'origine, en minuscules => valeur Baqio } (ex. { "rouge" => "red" }).
  # failure - code renvoyé pour un terme inconnu (ex. :color_unknown).
  def self.term(raw, terms:, failure:)
    key = raw.to_s.strip.downcase
    return Success(Parsed.new(value: nil)) if key.empty?
    return Failure(failure) unless terms.key?(key)

    Success(Parsed.new(value: terms[key]))
  end

  # Première année plausible pour un millésime : au-delà, c'est un autre nombre de quatre chiffres
  # (un lot, une contenance) et non une année de récolte.
  FIRST_VINTAGE_YEAR = 1900

  # Millésime écrit en fin de désignation (ex. "Coteaux Nord 2019" => "2019").
  # Une désignation sans millésime ("Cuvée Marie", "Haut Montcalm N.M.") n'en a pas : nil,
  # tout comme une année invraisemblable ("Cuvée 3000").
  def self.vintage(name)
    last_word = name.to_s.split.last.to_s
    return Success(Parsed.new(value: nil)) unless last_word.length == 4 && last_word.delete("0-9").empty?
    return Success(Parsed.new(value: nil)) unless vintage_years.cover?(last_word.to_i)

    Success(Parsed.new(value: last_word))
  end

  # Un millésime peut précéder la vendange (vin primeur vendu par anticipation) : l'année suivante est admise.
  def self.vintage_years
    (FIRST_VINTAGE_YEAR..Date.today.year + 1)
  end
  private_class_method :vintage_years

  # Contenant d'un produit, sous l'une des trois formes suivantes :
  #   "<libellé> - <volume>"  ex. "Bouteille - 75.0" : une unité de 75 cl ;
  #   "<unités> x <volume>"   ex. "6 x 75"          : un carton de 6 unités de 75 cl, signalé ;
  #   "<libellé> <unités>"    ex. "Carton 6"        : un carton de 6 unités de volume inconnu, signalé.
  #
  # types          - Hash { libellé du logiciel d'origine => type Baqio } (ex. { "Bouteille" => "bottle" }).
  # case_type      - type Baqio d'un contenant de plusieurs unités (ex. "case").
  # volume_unit_ml - nombre de millilitres de l'unité de volume du logiciel (10 pour des centilitres).
  #
  # Renvoie Parsed(value: { type:, units:, volume_ml: }). volume_ml est le volume d'une unité.
  def self.container(raw, types:, case_type:, volume_unit_ml:)
    text = raw.to_s.strip
    return Success(Parsed.new(value: nil)) if text.empty?

    label, volume = text.split(" - ", 2)
    if volume && types.key?(label) && decimal_number?(volume)
      return Success(Parsed.new(value: { type: types[label], units: 1, volume_ml: milliliters(volume, volume_unit_ml) }))
    end

    units, volume = text.split(" x ", 2)
    if volume && positive_integer?(units) && decimal_number?(volume)
      value = { type: case_type, units: Integer(units, 10), volume_ml: milliliters(volume, volume_unit_ml) }
      return Success(Parsed.new(value: value, notice: :container_read_as_case))
    end

    label, units = text.split(" ", 2)
    if units && types.key?(label) && positive_integer?(units)
      value = { type: types[label], units: Integer(units, 10), volume_ml: nil }
      return Success(Parsed.new(value: value, notice: :container_volume_missing))
    end

    Failure(:container_invalid)
  end

  # Nombre décimal positif, sans signe ni exposant : "13", "13.32" (pas ".5", "5.", "1e3" ni "1_000").
  def self.decimal_number?(text)
    return false if text.empty? || text.start_with?(".") || text.end_with?(".")

    text.delete("0-9.").empty? && text.count(".") <= 1
  end
  private_class_method :decimal_number?

  def self.positive_integer?(text)
    !text.empty? && text.delete("0-9").empty? && Integer(text, 10).positive?
  end
  private_class_method :positive_integer?

  def self.milliliters(volume, volume_unit_ml)
    (BigDecimal(volume) * volume_unit_ml).round.to_i
  end
  private_class_method :milliliters
end
