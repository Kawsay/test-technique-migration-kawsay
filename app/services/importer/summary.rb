class Importer::Summary
  # Type d'enregistrement écrit => libellé du bilan.
  ENTITIES = { customers: "clients" }.freeze

  def initialize(report)
    @report = report
  end

  def to_s
    (tallies + counts_by_level).join("\n")
  end

  private

  def tallies
    @report.tallies.map do |(source, entity), tally|
      "#{source}, #{ENTITIES.fetch(entity)} : #{tally.created} créés, #{tally.updated} mis à jour, #{tally.unchanged} inchangés"
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
