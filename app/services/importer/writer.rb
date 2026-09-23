# Écrit des enregistrements dans une table, sans doublon et sans réécrire ceux qui n'ont pas changé.
#
# Chaque enregistrement passe par son modèle ActiveRecord : ses validations s'appliquent, et le suivi des
# modifications (changed?) dit s'il est nouveau, modifié ou inchangé. Un enregistrement inchangé n'est pas
# réécrit, updated_at compris : l'écriture est idempotente.
#
# model   - classe ActiveRecord de la table (ex. Customer).
# key     - Array des colonnes de la clé naturelle, couverte par un index unique (ex. [:reference]).
# columns - Array des colonnes écrites.
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
    existing = existing_records(rows)
    records  = rows.map { |row| record_for(row, existing) }

    created = records.count { |record| record.new_record? }
    updated = records.count { |record| record.persisted? && record.changed? }

    # Un enregistrement invalide est une erreur de notre import (le contrat aurait dû le rejeter) : save! lève,
    # et aucun enregistrement n'est écrit, même dans une transaction déjà ouverte (requires_new).
    @model.transaction(requires_new: true) { records.each { |record| record.save! } }

    MigrationReport::Bilan.new(accepted: records.size, created: created, updated: updated,
                               unchanged: records.size - created - updated)
  end

  private

  # Enregistrements déjà en base parmi ceux à écrire, en une seule requête, rangés par clé.
  def existing_records(rows)
    return {} if rows.empty? # ActiveRecord ne sait pas écrire la condition d'une liste de clés vide

    keys    = rows.map { |row| key_of(row) }
    records = @model.where(@key => keys)

    records.index_by { |record| key_of(record) }
  end

  # L'enregistrement existant, ou un nouveau, avec les valeurs de la ligne.
  def record_for(row, existing)
    existing.fetch(key_of(row)) { @model.new }.tap do |record|
      record.assign_attributes(values_of(row))
    end
  end

  # Valeurs à écrire : toutes les colonnes, à nil quand la ligne ne les porte pas.
  def values_of(row)
    @columns.to_h { |column| [column, row[column]] }
  end

  # Valeurs de la clé d'une ligne (Hash) ou d'un enregistrement (ActiveRecord) : les deux se lisent avec [].
  def key_of(row_or_record)
    @key.map { |column| row_or_record[column] }
  end
end
