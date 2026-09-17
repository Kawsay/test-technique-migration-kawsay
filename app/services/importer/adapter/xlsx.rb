class Importer::Adapter::Xlsx < Importer::Adapter::Base
  def initialize(path, sheet:)
    super(path)
    @sheet = sheet
  end

  private

  def read_rows
    sheet = open_sheet
    rows  = {}

    # #first_row signifie "la première ligne NON vide" dans Roo
    return rows if sheet.first_row.nil?

    (sheet.first_row..sheet.last_row).each do |line|
      rows[line] = sheet.row(line)
    end

    rows
  end

  def open_sheet
    workbook = Roo::Excelx.new(@path)

    unless workbook.sheets.include?(@sheet)
      raise Importer::FileRejected, "#{file_name}, sheet #{@sheet} missing"
    end

    workbook.sheet(@sheet)
  rescue Zip::Error
    # https://github.com/roo-rb/roo/blob/f3e67741f5f13422e9231a9923579ff0067bdfd1/lib/roo/excelx.rb#L395
    raise Importer::FileRejected, "#{file_name} is not a readable Excel workbook"
  rescue IOError
    # https://github.com/roo-rb/roo/blob/f3e67741f5f13422e9231a9923579ff0067bdfd1/lib/roo/base.rb#L406
    raise Importer::FileRejected, "#{file_name} is missing"
  end
end
