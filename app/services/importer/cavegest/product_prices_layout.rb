# Disposition de l'export des tarifs de CaveGest 4.2 : un produit par ligne, avec un prix par grille tarifaire,
# regroupés en sections (« --- AOP ROUGES --- ») suivies d'un sous-total.
class Importer::Cavegest::ProductPricesLayout < Importer::Layout::Base
  # Position de la colonne (à partir de 0), champ, en-tête attendu.
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

  # Encodage et séparateur de l'export.
  FALLBACK_ENCODING = "Windows-1252".freeze
  COL_SEP           = ";".freeze

  # L'export commence par un commentaire (« … ATTENTION : la grille EXPO est saisie en TTC »)
  # et une ligne vide, avant l'en-tête.
  PREAMBLE_SIZE = 2

  # « --- AOP ROUGES --- » ouvre une section ; « SOUS-TOTAL AOP ROUGES;…;14 » la ferme.
  SECTION_MARK    = "---".freeze
  SUBTOTAL_PREFIX = "SOUS-TOTAL".freeze

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
