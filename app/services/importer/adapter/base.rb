class Importer::Adapter::Base
  def initialize(path)
    @path = path
  end

  def rows
    read_rows.map do |line, values|
      Importer::Adapter::Row.new(line:, values:)
    end
  end

  private

  def read_rows
    raise NotImplementedError, "#{self.class} must implement #read_rows"
  end

  def file_name
    File.basename(@path)
  end
end
