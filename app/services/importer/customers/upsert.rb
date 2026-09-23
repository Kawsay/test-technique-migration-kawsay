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

  # Deux clients qui partagent toutes ces valeurs sont probablement le même, saisi deux fois sous des
  # références différentes. La ville seule ou la raison sociale seule ne suffisent pas : une enseigne
  # a plusieurs établissements.
  IDENTITY = %i[company_name last_name first_name address1 zip city].freeze

  def initialize(accepted:, source:, report:)
    @accepted = accepted
    @source   = source
    @report   = report
  end

  def call
    accepted = without_duplicates
    report_possible_duplicates(accepted)

    writer = Importer::Writer.new(model: Customer, key: [KEY], columns: Importer::Customers.attributes)
    bilan  = writer.call(accepted.map { |candidate| candidate.attributes })

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

    group.each do |accepted|
      @report.add(level: :rejected, code: code, source: @source, line: accepted.record.line,
                  entity: entity(accepted), field: KEY, raw: accepted.attributes[KEY],
                  cells: accepted.record.cells)
      @report.discard_line(@source, accepted.record.line)
    end
  end

  # Deux références différentes pour les mêmes valeurs : les deux sont reprises, puisque rien ne prouve
  # le doublon, mais le client doit vérifier avant de se retrouver avec deux fiches pour un même tiers.
  def report_possible_duplicates(accepted)
    groups = accepted.group_by { |candidate| IDENTITY.map { |field| candidate.attributes[field] } }

    groups.each do |values, group|
      next if group.size == 1

      group.each do |candidate|
        @report.add(level: :suspect, code: :possible_duplicate, source: @source, line: candidate.record.line,
                    entity: entity(candidate), raw: values.compact.join(", "), cells: candidate.record.cells)
      end
    end
  end

  def entity(accepted)
    "Client #{accepted.attributes[KEY]}"
  end
end
