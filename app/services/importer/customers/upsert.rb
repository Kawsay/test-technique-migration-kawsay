# Écrit en base les clients préparés par Importer::Customers::Prepare, sans jamais créer de doublon.
#
# L'écriture est idempotente (voir Importer::Writer) : rejouer l'import sur le même fichier ne modifie
# aucune ligne.
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
    writer = Importer::Writer.new(model: Customer, key: [KEY], columns: Importer::Customers::ATTRIBUTES)
    bilan  = writer.call(without_duplicates.map { |accepted| accepted.attributes })

    @report.record_bilan(@source, :customers, bilan)
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

  def entity(accepted)
    "Client #{accepted.attributes[KEY]}"
  end
end
