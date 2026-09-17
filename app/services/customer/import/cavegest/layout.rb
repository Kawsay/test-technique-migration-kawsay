# Disposition de l'export clients de CaveGest 4.2 : ce que contient chaque colonne,
# et les lignes du fichier qui ne sont pas des clients.
#
# Reçoit un adaptateur de format (tout objet répondant à #rows) : la disposition ne dépend pas
# du format du fichier, seulement de son contenu.
#
# TODO: prendre en compte les différentes versions de Cavegest
class Customer::Import::Cavegest::Layout
  # line  - Integer, numéro de ligne tel que le client le voit dans son fichier.
  # cells - Hash { champ => valeur brute }, ex. { reference: "T00001", zip: 69002, … }.
  Record = Data.define(:line, :cells)

  # position - Integer, position de la colonne (à partir de 0).
  # name     - String, en-tête de la colonne ; nil si l'en-tête est vide.
  # filled   - Integer, nombre de lignes, hors en-tête, où la colonne contient une valeur.
  IgnoredColumn = Data.define(:position, :name, :filled)

  # Position de la colonne (à partir de 0), champ, en-tête attendu.
  # Les blocs facturation et livraison ont des en-têtes identiques (seule la position les distingue).
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

  # Dernière ligne de l'export : « TOTAL » dans la première colonne, puis le nombre de clients annoncé.
  TOTAL_MARKER = "TOTAL".freeze

  def initialize(rows)
    @header    = rows.first
    @data_rows = rows.drop(1)
  end

  # Renvoie les lignes de clients, sans l'en-tête, les lignes vides ni la ligne TOTAL.
  #
  # Lève Importer::FileRejected si l'en-tête ne correspond pas à la disposition attendue :
  # les colonnes seraient mal interprétées.
  def records
    check_header

    customer_rows = @data_rows.reject { |row| empty?(row) || total?(row) }
    customer_rows.map { |row| Record.new(line: row.line, cells: cells(row)) }
  end

  # Renvoie les colonnes présentes au-delà des colonnes attendues, dans l'en-tête ou dans les lignes.
  #
  # Ces colonnes ne décalent pas les colonnes attendues : le fichier reste lisible,
  # mais leurs valeurs ne sont pas reprises et doivent être signalées.
  def ignored_columns
    ignored_columns = []

    (COLUMNS.size...widest_row_size).each do |position|
      name   = header_name(position)
      filled = filled_count(position)

      next if name.nil? && filled.zero?

      ignored_columns << IgnoredColumn.new(position: position, name: name, filled: filled)
    end

    ignored_columns
  end

  private

  def check_header
    raise Importer::FileRejected, "header row missing" if @header.nil?

    differences = []

    COLUMNS.each do |position, _field, expected|
      found = @header.values[position]
      differences << "column #{position + 1}: expected \"#{expected}\", found \"#{found}\"" if found != expected
    end

    raise Importer::FileRejected, "unexpected header (#{differences.join('; ')})" if differences.any?
  end

  def cells(row)
    cells = {}

    COLUMNS.each do |position, field, _header|
      cells[field] = row.values[position]
    end

    cells
  end

  def widest_row_size
    sizes = @data_rows.map { |row| row.values.size }
    sizes << @header.values.size unless @header.nil?

    sizes.max || 0
  end

  def header_name(position)
    return nil if @header.nil?

    @header.values[position]
  end

  def filled_count(position)
    @data_rows.count { |row| !row.values[position].nil? }
  end

  def empty?(row)
    row.values.all?(&:nil?)
  end

  def total?(row)
    row.values.first == TOTAL_MARKER
  end
end
