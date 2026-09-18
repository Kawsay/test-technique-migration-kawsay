module Importer::Customers
  DATABASE_COLUMNS = %i[id created_at updated_at].freeze

  ATTRIBUTES = (Customer.column_names.map(&:to_sym) - DATABASE_COLUMNS).freeze
end
