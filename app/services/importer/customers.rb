module Importer::Customers
  # Colonnes écrites par l'import : toutes celles de la table, hors colonnes gérées par la base.
  # Lues à la première demande, et non au chargement : la table n'existe pas encore quand bin/setup
  # crée la base.
  def self.attributes
    @attributes ||= (Customer.column_names.map(&:to_sym) - Importer::DATABASE_COLUMNS).freeze
  end
end
