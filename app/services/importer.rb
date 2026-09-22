module Importer
  # Le fichier du client ne peut pas être importé du tout : anomalie de ses données, pas un bug technique.
  class FileRejected < StandardError; end

  # Colonnes gérées par la base, jamais lues dans un fichier.
  DATABASE_COLUMNS = %i[id created_at updated_at].freeze
end
