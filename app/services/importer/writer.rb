# Écrit des enregistrements dans une table, sans doublon et sans réécrire ceux qui n'ont pas changé.
#
# L'écriture est idempotente : écrire deux fois les mêmes enregistrements ne modifie aucune ligne,
# updated_at compris. Seuls les enregistrements nouveaux ou réellement modifiés sont écrits.
#
# model   - classe ActiveRecord de la table (ex. Customer).
# key     - Array des colonnes de la clé naturelle, couverte par un index unique (ex. [:reference]).
# columns - Array des colonnes écrites : chaque enregistrement est comparé à la base sur ces colonnes.
class Importer::Writer
  def initialize(model:, key:, columns:)
    @model   = model
    @key     = key
    @columns = columns
  end

  # rows - Array de Hash, un par enregistrement, sans doublon de clé. Une colonne absente d'un
  #        enregistrement est écrite à nil : une valeur que le fichier ne porte plus est effacée.
  #
  # Renvoie le bilan de l'écriture (MigrationReport::Bilan).
  def call(rows)
    rows     = rows.map { |row| @columns.to_h { |column| [column, row[column]] } }
    existing = existing_rows(rows)

    to_create = rows.reject { |row| existing.key?(key_of(row)) }
    to_update = rows.select { |row| existing.key?(key_of(row)) && existing[key_of(row)] != row }

    write(to_create + to_update)

    MigrationReport::Bilan.new(accepted: rows.size, created: to_create.size, updated: to_update.size,
                               unchanged: rows.size - to_create.size - to_update.size)
  end

  private

  def key_of(row)
    row.values_at(*@key)
  end

  # Enregistrements déjà en base parmi ceux à écrire, sous la même forme, pour être comparés colonne par colonne.
  # Avec une clé de plusieurs colonnes, la requête peut en ramener d'autres : ils ne sont jamais consultés.
  def existing_rows(rows)
    return {} if rows.empty?

    conditions = @key.to_h { |column| [column, rows.map { |row| row[column] }.uniq] }

    @model.where(conditions)
      .pluck(*@columns)
      .map { |values| @columns.zip(values).to_h }
      .index_by { |row| key_of(row) }
  end

  # upsert_all écrit toutes les lignes dans une seule requête : les valeurs sont écrites dans le SQL,
  # sans paramètres liés. Un fichier bien plus gros demanderait de découper l'écriture (each_slice).
  def write(rows)
    return if rows.empty?

    @model.upsert_all(rows.sort_by { |row| key_of(row) }, unique_by: @key, record_timestamps: true)
  end
end
