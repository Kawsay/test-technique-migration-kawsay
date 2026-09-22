# Import des produits et de leurs tarifs : préparation des lignes du fichier, règles métier, puis écriture en base.
module Importer::ProductPrices
  PRODUCT_ATTRIBUTES = (Product.column_names.map(&:to_sym) - Importer::DATABASE_COLUMNS).freeze
  PRICE_ATTRIBUTES   = (ProductPrice.column_names.map(&:to_sym) - Importer::DATABASE_COLUMNS).freeze
end
