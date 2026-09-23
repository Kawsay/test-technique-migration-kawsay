class MigrationReport
  # rejected : pas en base                            -> le client corrige son fichier
  # repaired : en base, valeur modifiée par une règle -> le client valide la règle
  # suspect  : en base, valeur douteuse               -> le client vérifie
  # info     : transformation attendue                -> rien à faire
  LEVELS = %i(rejected repaired suspect info).freeze

  # Ce que chaque niveau demande au client, dans l'ordre de gravité.
  LEVEL_LABELS = {
    rejected: "Non repris",
    repaired: "Repris avec correction automatique",
    suspect:  "Repris, à vérifier",
    info:     "Pour information"
  }.freeze

  # Libellé lisible par le client, un par code émis. Un code sans libellé s'affiche tel quel :
  # le rapport reste lisible, et un test vérifie qu'il n'en manque aucun.
  LABELS = {
    # Fichier
    file_rejected:               "Fichier non repris",
    column_ignored:              "Colonne en trop, non reprise",

    # Ligne
    reference_missing:           "Référence absente",
    name_missing:                "Ni raison sociale, ni nom, ni prénom",
    kind_unknown:                "Type de tiers inconnu",
    vat_rate_missing:            "Taux de TVA absent ou inconnu",
    duplicate_identical:         "Référence présente sur plusieurs lignes identiques",
    duplicate_conflict:          "Référence présente sur plusieurs lignes différentes",

    # Clients
    zip_padded:                  "Code postal complété d'un zéro initial (perdu par le tableur)",
    zip_invalid:                 "Code postal illisible, non repris",
    country_defaulted:           "Pays absent, pays par défaut appliqué",
    country_unknown:             "Pays inconnu, non repris",
    phone_leading_zero_restored: "Téléphone complété d'un zéro initial (perdu par le tableur)",
    phone_unassigned:            "Téléphone dans une plage non attribuée en métropole",
    phone_invalid:               "Téléphone illisible, non repris",
    email_invalid:               "Adresse e-mail invalide, non reprise",
    date_invalid:                "Date illisible, non reprise",
    excise_without_vat_number:   "Numéro d'accise sans numéro de TVA : facturation impossible",
    flag_invalid:                "Oui/non illisible, non repris",
    kind_reseller_as_customer:   "Revendeur repris comme client",

    # Produits et tarifs
    color_unknown:               "Couleur inconnue, non reprise",
    color_missing:               "Couleur absente",
    color_inconsistent_with_section: "Couleur en désaccord avec la section du catalogue",
    container_missing:           "Contenant absent : volume et conditionnement inconnus",
    section_unknown:             "Section inconnue : appellation et type de produit non repris",
    container_invalid:           "Contenant illisible, conservé tel quel",
    container_volume_missing:    "Contenant sans volume, conservé tel quel",
    container_read_as_case:      "Contenant lu comme un carton",
    vat_rate_invalid:            "Taux de TVA illisible",
    vat_rate_unknown:            "Taux de TVA inapplicable en France",
    integer_invalid:             "Nombre entier illisible, non repris",
    amount_invalid:              "Montant illisible, tarif non repris",
    amount_not_positive:         "Montant nul ou négatif, tarif non repris",
    price_ttc_converted:         "Prix saisi TTC, converti en HT",
    price_grids_inconsistent:    "Prix incohérent avec celui d'une autre grille",
    price_grid_empty:            "Grille sans prix : aucun tarif créé",
    price_removed:               "Grille désormais vide : tarif retiré de la base"
  }.freeze

  # Un événement notable survenu pendant la reprise, rattaché à une ligne d'un fichier source.
  #
  # level  - Symbol, l'un de LEVELS. Détermine ce que le client doit faire :
  #          :rejected  l'enregistrement n'est pas en base, le client corrige son fichier ;
  #          :repaired  il est en base avec une valeur modifiée par une règle, le client valide la règle ;
  #          :suspect   il est en base mais une valeur est douteuse ou a été vidée, le client vérifie ;
  #          :info      transformation attendue, rien à faire.
  # code   - Symbol stable identifiant le problème (ex. :zip_padded). Sert aux tests et aux
  #          regroupements ; le libellé lisible par le client en est dérivé, jamais l'inverse.
  # source - String, nom du fichier d'origine (ex. "export_clients_cavegest.xlsx").
  # line   - Integer, numéro de ligne dans le fichier, tel que le client le voit dans son tableur.
  #          nil pour un événement qui concerne tout le fichier (ex. import interrompu).
  # entity - String, enregistrement concerné en termes métier (ex. "Client T00022").
  #          nil si la ligne n'a pas pu être identifiée.
  # field  - Symbol, attribut concerné (ex. :zip). nil si l'événement porte sur toute la ligne.
  # raw      - valeur lue dans le fichier, avant toute transformation (ex. 1000).
  # value    - valeur retenue en base (ex. "01000") ; nil si rien n'a été enregistré.
  #            raw et value ensemble rendent une correction automatique vérifiable.
  # previous - valeur qui était en base avant la reprise, quand celle-ci l'efface ou la remplace
  #            (ex. le montant d'un tarif retiré) ; nil sinon.
  # cells    - Hash de la ligne d'origine complète, pour que le client puisse corriger
  #            et réimporter une ligne rejetée. nil pour un événement sans ligne.
  Issue = Data.define(:level, :code, :source, :line, :entity, :field, :raw, :value, :previous, :cells) do
    # Libellé lisible par le client, à défaut le code lui-même : aucun événement ne doit rester muet.
    def message
      LABELS.fetch(code, code.to_s)
    end

    def level_label
      LEVEL_LABELS.fetch(level)
    end
  end

  # Bilan de l'écriture en base d'un type d'enregistrement lu dans un fichier (ex. les produits du fichier
  # des tarifs), calculé une seule fois après l'écriture, en comparant les enregistrements à écrire avec
  # ceux déjà présents.
  #
  # accepted  - Integer, enregistrements prêts à être écrits : ils ont passé les contrôles et
  #             le dédoublonnage. Ce n'est pas le nombre de lignes lues : les lignes rejetées
  #             et les doublons n'y figurent pas.
  # created   - Integer, enregistrements absents de la base, créés.
  # updated   - Integer, enregistrements déjà en base dont au moins une valeur a changé.
  # unchanged - Integer, enregistrements déjà en base, identiques : rien n'a été écrit.
  #
  # accepted == created + updated + unchanged.
  # Lors d'un rejeu sur le même fichier, created et updated doivent valoir 0.
  Bilan = Data.define(:accepted, :created, :updated, :unchanged) do
    def initialize(accepted:, created:, updated:, unchanged:)
      unless accepted == created + updated + unchanged
        raise ArgumentError, "bilan incohérent : #{accepted} != #{created} + #{updated} + #{unchanged}"
      end

      super
    end
  end

  def initialize
    @issues    = []
    @discarded = []
    @bilans    = {}
    @declared  = {}
  end

  def add(level:, code:, source:, **attrs)
    raise ArgumentError, "unknown level : #{level}" unless LEVELS.include?(level)
    raise ArgumentError, "level must be a symbol"   unless level.is_a?(Symbol)

    issue =  Issue.new(level:, code:, source:, line: nil, entity: nil, field: nil,
                      raw: nil, value: nil, previous: nil, cells: nil, **attrs)
    @issues << issue
    issue
  end

  # entity - Symbol, type d'enregistrement écrit (ex. :products) : un fichier peut en alimenter plusieurs.
  def record_bilan(source, entity, bilan)
    write_once(@bilans, [source, entity], bilan)
  end

  # Ligne finalement non reprise, alors que ses anomalies ont déjà été journalisées : c'est le cas d'un
  # doublon, qui n'est connu qu'à l'écriture, une fois toutes les lignes lues. Ses autres anomalies
  # deviennent sans objet pour le client (voir #issues_for_client).
  def discard_line(source, line)
    @discarded << [source, line]
  end

  def record_declared(source, **totals)
    write_once(@declared, source, totals.freeze)
  end

  def issues
    @issues.dup.freeze
  end

  def bilans
    @bilans.dup.freeze
  end

  def declared
    @declared.dup.freeze
  end

  # Anomalies telles qu'elles sont présentées au client : une ligne non reprise n'y porte que les raisons
  # de son rejet. Une valeur corrigée ou douteuse sur une ligne absente de la base n'appelle aucune action.
  #
  # Le journal complet (#issues) les conserve : il enregistre tout ce qui s'est passé pendant la reprise.
  def issues_for_client
    discarded = @discarded.uniq

    issues.reject { |issue| issue.level != :rejected && discarded.include?([issue.source, issue.line]) }
  end

  def by_level(level)
    issues_for_client.select { |issue| issue.level == level }
  end

  # Anomalies du client, des plus graves aux moins graves, puis dans l'ordre des lignes du fichier.
  def issues_by_severity
    issues_for_client.sort_by { |issue| [LEVELS.index(issue.level), issue.source, issue.line || 0] }
  end

  # Codes émis qui n'ont pas de libellé : ils s'afficheraient tels quels au client.
  def codes_without_label
    issues.map { |issue| issue.code }.uniq.reject { |code| LABELS.key?(code) }
  end

  private

  def write_once(store, key, value)
    raise ArgumentError, "déjà enregistré pour #{key}" if store.key?(key)

    store[key] = value
  end
end
