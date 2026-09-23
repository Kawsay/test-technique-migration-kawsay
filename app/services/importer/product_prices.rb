# Import des produits et de leurs tarifs : préparation des lignes du fichier, règles métier, puis écriture en base.
module Importer::ProductPrices
  # Colonnes écrites par l'import : toutes celles de la table, hors colonnes gérées par la base.
  # Lues à la première demande, et non au chargement : les tables n'existent pas encore quand bin/setup
  # crée la base.
  def self.product_attributes
    @product_attributes ||= (Product.column_names.map(&:to_sym) - Importer::DATABASE_COLUMNS).freeze
  end

  def self.price_attributes
    @price_attributes ||= (ProductPrice.column_names.map(&:to_sym) - Importer::DATABASE_COLUMNS).freeze
  end
end
