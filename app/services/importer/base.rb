class Importer::Base
  attr_reader :path, :report

  def initialize(path, report: MigrationReport.new)
    @path   = path
    @report = report
  end

  def call
    raise NotImplementedError
  end

  private

  def source
    File.basename(path)
  end
end
