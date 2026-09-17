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
end
