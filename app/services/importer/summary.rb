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

  def counts_by_level
    MigrationReport::LEVELS.filter_map do |level|
      issues = @report.by_level(level)
      next if issues.empty?

      counts = issues.group_by { |issue| issue.code }
        .map { |code, found| "#{code} (#{found.size})" }
        .join(", ")

      "#{level} : #{counts}"
    end
  end
end
