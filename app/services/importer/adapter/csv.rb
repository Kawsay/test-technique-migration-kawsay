# Lit un fichier CSV, ligne par ligne, et renvoie ses valeurs en UTF-8, quel que soit l'encodage du fichier.
class Importer::Adapter::Csv < Importer::Adapter::Base
  # Marque que certains éditeurs placent en tête d'un fichier UTF-8 (BOM) : elle n'appartient pas aux données.
  BOM = "\uFEFF".freeze

  def initialize(path, fallback_encoding:, col_sep:)
    super(path)
    @fallback_encoding = fallback_encoding
    @col_sep           = col_sep
  end

  private

  def read_rows
    bytes    = File.binread(@path)
    encoding = source_encoding(bytes)
    text     = bytes.force_encoding(encoding).encode(Encoding::UTF_8).delete_prefix(BOM)

    rows_of(text)
  rescue Errno::ENOENT
    raise Importer::FileRejected, "#{file_name} is missing"
  rescue Encoding::UndefinedConversionError
    raise Importer::FileRejected, "#{file_name} is neither UTF-8 nor #{@fallback_encoding}"
  rescue ::CSV::MalformedCSVError => error
    raise Importer::FileRejected, "#{file_name} is not a readable CSV file (#{error.message})"
  end

  def source_encoding(bytes)
    utf8 = bytes.dup.force_encoding(Encoding::UTF_8)

    utf8.valid_encoding? ? Encoding::UTF_8 : @fallback_encoding
  end

  def rows_of(text)
    rows = {}
    line = 1
    csv  = ::CSV.new(text, col_sep: @col_sep)

    csv.each do |values|
      rows[line] = values
      line += csv.line.lines.size
    end

    rows
  end
end
