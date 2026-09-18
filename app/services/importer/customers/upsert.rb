# Écrit en base les clients préparés par Importer::Customers::Prepare, sans jamais créer de doublon.
#
# L'écriture est idempotente : rejouer l'import sur le même fichier ne modifie aucune ligne,
# updated_at compris. Seules les lignes nouvelles ou réellement modifiées sont écrites.
#
# accepted - Array des Importer::Customers::Prepare::Accepted à écrire.
# source   - nom du fichier d'origine, pour le rapport.
# report   - MigrationReport.
class Importer::Customers::Upsert
  # Clé naturelle : la référence du client dans le logiciel source (index unique en base).
  KEY = :reference

  def initialize(accepted:, source:, report:)
    @accepted = accepted
    @source   = source
    @report   = report
  end

  def call
    attributes = attributes_of(without_duplicates)
    existing   = existing_attributes(attributes)

    to_create = attributes.reject { |customer| existing.key?(customer[KEY]) }
    to_update = attributes.select { |customer| existing.key?(customer[KEY]) && existing[customer[KEY]] != customer }

    write(to_create + to_update)

    @report.record_tally(@source, accepted: attributes.size, created: to_create.size, updated: to_update.size,
                         unchanged: attributes.size - to_create.size - to_update.size)
  end

  private

  # Une référence présente plusieurs fois n'est reprise sous aucune de ses versions : rien ne permet
  # de choisir laquelle est la bonne, et l'ordre de lecture ne doit pas en décider à notre place.
  def without_duplicates
    kept, duplicated = @accepted.group_by { |accepted| accepted.attributes[KEY] }.partition do |_reference, group|
      group.size == 1
    end

    duplicated.each { |_reference, group| report_duplicates(group) }

    kept.flat_map { |_reference, group| group }
  end

  def report_duplicates(group)
    # Les lignes d'une même référence portent-elles toutes les mêmes valeurs ?
    identical = group.map { |accepted| accepted.attributes }.uniq.one?
    code      = identical ? :duplicate_identical : :duplicate_conflict
    lines     = group.map { |accepted| accepted.record.line }

    group.each do |accepted|
      @report.add(level: :rejected, code: code, source: @source, line: accepted.record.line,
                  entity: entity(accepted), field: KEY, raw: accepted.attributes[KEY], value: lines.join(", "),
                  cells: accepted.record.cells)
    end
  end

  # Attributs à écrire, tous complétés des colonnes que leur ligne ne renseigne pas.
  def attributes_of(accepted)
    accepted.map do |candidate|
      customer_attributes.to_h { |column| [column, candidate.attributes[column]] }
    end
  end

  # Clients déjà en base parmi ceux à écrire, sous la même forme, pour être comparés attribut par attribut.
  def existing_attributes(attributes)
    return {} if attributes.empty?

    references = attributes.map { |customer| customer[KEY] }

    Customer.where(KEY => references)
      .pluck(*customer_attributes)
      .map { |values| customer_attributes.zip(values).to_h }
      .index_by { |customer| customer[KEY] }
  end

  # upsert_all écrit toutes les lignes dans une seule requête : les valeurs sont écrites dans le SQL,
  # sans paramètres liés. Un fichier bien plus gros demanderait de découper l'écriture (each_slice).
  def write(attributes)
    return if attributes.empty?

    Customer.upsert_all(
      attributes.sort_by { |customer| customer[KEY] },
      unique_by: KEY,
      record_timestamps: true
    )
  end

  def customer_attributes
    Importer::Customers::ATTRIBUTES
  end


  def entity(accepted)
    "Client #{accepted.attributes[KEY]}"
  end
end
