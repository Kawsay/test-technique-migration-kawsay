class Importer::Cavegest::ProductPricesLayout < Importer::Layout::Base
  COLUMNS = [
    [0,  :reference,   "Ref"],
    [1,  :name,        "Désignation"],
    [2,  :container,   "Contenant"],
    [3,  :color,       "Couleur"],
    [4,  :vat_rate,    "TVA"],
    [5,  :price_depc,  "DEPC"],
    [6,  :price_chr,   "CHR"],
    [7,  :price_expo,  "EXPO"],
    [8,  :price_part,  "PART"],
    [9,  :price_salon, "SALON"],
    [10, :stock,       "Stock"]
  ].freeze

  FALLBACK_ENCODING = "Windows-1252".freeze
  COL_SEP           = ";".freeze

  PREAMBLE_SIZE = 2

  SECTION_MARK    = "---".freeze
  SUBTOTAL_PREFIX = "SOUS-TOTAL".freeze

  EMPTY_MARKERS = [].freeze # aucun marqueur de valeur absente dans cet export

  PRICE_GRIDS = {
    "DEPC"  => :price_depc,
    "CHR"   => :price_chr,
    "EXPO"  => :price_expo,
    "PART"  => :price_part,
    "SALON" => :price_salon
  }.freeze

  # Grilles saisies toutes taxes comprises, d'après le préambule de l'export
  # ("ATTENTION : la grille EXPO est saisie en TTC") : converties en HT avec la TVA du produit.
  TTC_GRIDS = ["EXPO"].freeze

  # Grilles dont les prix HT sont égaux dans l'export : EXPO converti en HT = DEPC au centime près.
  # Sert à repérer une erreur de saisie (HAU214 a un DEPC à 34,35 € alors
  # qu'EXPO converti donne 7,37 €)
  EQUAL_PRICE_GRIDS = [["EXPO", "DEPC"]].freeze

  COLORS = { "rouge" => "red", "blanc" => "white", "rosé" => "rose" }.freeze

  CONTAINER_TYPES = {
    "Bouteille"   => "bottle",
    "½ Bouteille" => "bottle",
    "Magnum"      => "bottle",
    "Litre"       => "bottle",
    "BIB"         => "bib",
    "Carton"      => "case"
  }.freeze
  CASE_CONTAINER_TYPE     = "case".freeze
  CONTAINER_VOLUME_UNIT_ML = 10

  # Sections dont le nom annonce une couleur : un désaccord avec la colonne « Couleur » est signalé.
  SECTION_COLORS = { "AOP ROUGES" => "red", "AOP BLANCS" => "white" }.freeze

  # Sections de l'export => niveau d'appellation et type de produit Baqio
  # (voir Product::APPELLATIONS et Product::PRODUCT_TYPES).
  SECTIONS = {
    "AOP ROUGES"    => { appellation: "aop",           product_type: "still_wine" },
    "AOP BLANCS"    => { appellation: "aop",           product_type: "still_wine" },
    "IGP"           => { appellation: "igp",           product_type: "still_wine" },
    "VIN DE FRANCE" => { appellation: "vin_de_france", product_type: "still_wine" },
    "EFFERVESCENTS" => { appellation: nil,             product_type: "sparkling_wine" },
    "DIVERS"        => { appellation: nil,             product_type: "other" }
  }.freeze

  # rows - Array des Importer::Adapter::Row du fichier, préambule compris.
  def initialize(rows)
    super(rows.drop(PREAMBLE_SIZE))
  end

  # Section du produit (ex. "AOP ROUGES") : titre de la dernière section qui précède sa ligne.
  def section_for(record)
    sections_by_line[record.line]
  end

  private

  def columns
    COLUMNS
  end

  def skipped_row?(row)
    section?(row) || subtotal?(row)
  end

  def section?(row)
    row.values.first.to_s.start_with?(SECTION_MARK)
  end

  def subtotal?(row)
    row.values.first.to_s.start_with?(SUBTOTAL_PREFIX)
  end

  # "--- AOP ROUGES ---" => "AOP ROUGES"
  def section_name(row)
    row.values.first.delete_prefix(SECTION_MARK).delete_suffix(SECTION_MARK).strip
  end

  def sections_by_line
    return @sections_by_line if @sections_by_line

    @sections_by_line = {}
    current_section   = nil

    @data_rows.each do |row|
      current_section = section_name(row) if section?(row)
      @sections_by_line[row.line] = current_section
    end

    @sections_by_line
  end
end
