module Importer::Customers
  ATTRIBUTES = (Customer.column_names.map(&:to_sym) - Importer::DATABASE_COLUMNS).freeze
end
