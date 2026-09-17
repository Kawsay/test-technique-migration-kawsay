# Adaptateurs de format : lisent un fichier (XLSX, CSV…) et produisent des lignes brutes,
# de même forme quel que soit le format, pour que la suite du traitement n'en dépende pas.
#
# Un adaptateur ne connaît que le format : ni la signification des colonnes,
# ni les lignes particulières d'un export (en-tête, totaux…).
module Importer::Adapter
  # line   - Integer, numéro de ligne tel que le client le voit dans son fichier (à partir de 1).
  # values - Array des valeurs bruts de la ligne, par position de colonne (à partir de 0).
  Row = Data.define(:line, :values)
end
