# Les anomalies d'une reprise, dans un fichier que le client ouvre dans son tableur.
#
# Une ligne par anomalie, des plus graves aux moins graves : il filtre sur la colonne « Gravité » pour voir
# d'abord ce qui n'est pas repris. Les corrections automatiques y figurent aussi, pour qu'il puisse les
# valider et constater que rien n'a été fait dans son dos.
#
# Le fichier est écrit comme les tableurs français l'attendent : séparateur « ; » et marque d'ordre des
# octets (BOM), sans quoi Excel met tout dans une colonne et abîme les accents.
class Importer::IssuesCsv
  HEADERS = ["Gravité", "Fichier", "Ligne", "Enregistrement", "Champ", "Anomalie",
             "Valeur lue", "Valeur retenue", "Valeur remplacée"].freeze

  COL_SEP = ";".freeze
  BOM     = "﻿".freeze

  # Chemin du rapport d'un fichier source, horodaté pour ne pas écraser celui de la veille.
  def self.path_for(source, directory: REPORT_DIR)
    File.join(directory, "anomalies-#{File.basename(source, '.*')}-#{Time.now.strftime('%Y%m%d-%H%M%S')}.csv")
  end

  def initialize(report)
    @report = report
  end

  # Écrit le fichier et renvoie son chemin.
  def write(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, BOM + to_csv)

    path
  end

  def to_csv
    CSV.generate(col_sep: COL_SEP) do |csv|
      csv << HEADERS
      @report.issues_by_severity.each { |issue| csv << row(issue) }
    end
  end

  private

  def row(issue)
    [issue.level_label, issue.source, issue.line, issue.entity, issue.field, issue.message,
     value(issue.raw), value(issue.value), value(issue.previous)]
  end

  # Un montant s'écrit "13.32" et non "0.1332e2", et une cellule vide reste vide.
  def value(value)
    value.is_a?(BigDecimal) ? value.to_s("F") : value
  end
end
