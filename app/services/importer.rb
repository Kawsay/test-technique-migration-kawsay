module Importer
  # Le fichier du client ne peut pas être importé du tout : anomalie de ses données, pas un bug technique.
  class FileRejected < StandardError; end
end
