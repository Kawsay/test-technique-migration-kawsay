# Résumé d'une reprise, affiché en fin d'import : ce qui est entré en base, et ce qui demande une action.
#
# Le détail des anomalies, ligne par ligne, est dans le fichier écrit par Importer::IssuesCsv.
class Importer::Summary
  # Type d'enregistrement écrit => libellé du bilan.
  ENTITIES = { customers: "clients", products: "produits", product_prices: "tarifs" }.freeze

  def initialize(report)
    @report = report
  end

  def to_s
    (bilans + counts_by_level).join("\n")
  end

  private

  def bilans
    @report.bilans.map do |(source, entity), bilan|
      "#{source}, #{ENTITIES.fetch(entity)} : #{bilan.created} créés, #{bilan.updated} mis à jour, #{bilan.unchanged} inchangés"
    end
  end

  # Un bloc par niveau, du plus grave au moins grave, avec le libellé de chaque anomalie et son nombre.
  def counts_by_level
    MigrationReport::LEVELS.flat_map do |level|
      issues = @report.by_level(level)
      next [] if issues.empty?

      ["", "#{MigrationReport::LEVEL_LABELS.fetch(level)} (#{issues.size}) :", *counts_by_code(issues)]
    end
  end

  def counts_by_code(issues)
    issues.group_by { |issue| issue.message }
      .sort_by { |_message, found| -found.size }
      .map { |message, found| "  #{found.size.to_s.rjust(5)}  #{message}" }
  end
end
