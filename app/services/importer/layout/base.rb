# Contrat commun à toutes les dispositions : chaque disposition propre à un logiciel en hérite.
#
# Toute disposition peut remplacer une autre sans que la suite du traitement ne change :
# - #records renvoie des Record, sans l'en-tête, les lignes vides
#   ni les lignes propres à l'export (totaux…), avec le numéro de ligne du fichier ;
# - #ignored_columns renvoie des IgnoredColumn ;
# - un en-tête absent ou différent de celui attendu lève Importer::FileRejected.
#
# Une sous-classe décrit son export : ses colonnes (#columns, obligatoire)
# et, si besoin, les lignes à écarter en plus des lignes vides (#skipped_row?).
class Importer::Layout::Base
  # Une ligne de données, cellules nommées.
  #
  # line  - Integer, numéro de ligne tel que le client le voit dans son fichier.
  # cells - Hash { champ => valeur brute }, ex. { reference: "T00001", zip: 69002, … }.
  Record = Data.define(:line, :cells)

  # Une colonne présente au-delà des colonnes attendues : elle n'est pas reprise.
  #
  # position - Integer, position de la colonne (à partir de 0).
  # name     - String, en-tête de la colonne ; nil si l'en-tête est vide.
  # filled   - Integer, nombre de lignes, hors en-tête, où la colonne contient une valeur.
  IgnoredColumn = Data.define(:position, :name, :filled)

  # rows - Array des Importer::Adapter::Row du fichier, en-tête compris.
  def initialize(rows)
    @header    = rows.first
    @data_rows = rows.drop(1)
  end

  # Lève Importer::FileRejected si l'en-tête ne correspond pas à la disposition attendue :
  # les colonnes seraient mal interprétées.
  def records
    check_header

    kept_rows = @data_rows.reject { |row| empty?(row) || skipped_row?(row) }
    kept_rows.map { |row| Record.new(line: row.line, cells: cells(row)) }
  end

  # Colonnes présentes au-delà des colonnes attendues, dans l'en-tête ou dans les lignes.
  #
  # Elles ne décalent pas les colonnes attendues : le fichier reste lisible,
  # mais leurs valeurs ne sont pas reprises et doivent être signalées.
  def ignored_columns
    ignored_columns = []

    (columns.size...widest_row_size).each do |position|
      name   = header_name(position)
      filled = filled_count(position)

      next if name.nil? && filled.zero?

      ignored_columns << IgnoredColumn.new(position: position, name: name, filled: filled)
    end

    ignored_columns
  end

  private

  # Doit renvoyer les colonnes attendues : Array de [position, champ, en-tête attendu],
  # positions à partir de 0, dans l'ordre du fichier.
  def columns
    raise NotImplementedError, "#{self.class} must implement #columns"
  end

  # Lignes propres à l'export, à écarter en plus des lignes vides. Aucune par défaut.
  def skipped_row?(_row)
    false
  end

  def check_header
    raise Importer::FileRejected, "header row missing" if @header.nil?

    differences = []

    columns.each do |position, _field, expected|
      found = @header.values[position]
      differences << "column #{position + 1}: expected \"#{expected}\", found \"#{found}\"" if found != expected
    end

    raise Importer::FileRejected, "unexpected header (#{differences.join('; ')})" if differences.any?
  end

  def cells(row)
    cells = {}

    columns.each do |position, field, _header|
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
end
