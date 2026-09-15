class Importer::Audit
  def self.call = new.call

  def call
    raise NotImplementedError
  end

  def to_s
    call.to_s
  end
end
