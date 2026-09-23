# == Schema Information
#
# Table name: products
#
#  id                  :bigint           not null, primary key
#  appellation         :string
#  color               :string
#  container_label     :string
#  container_type      :string
#  name                :string           not null
#  product_type        :string
#  reference           :string           not null
#  stock               :integer
#  units_per_container :integer
#  vat_rate            :decimal(5, 2)
#  vintage             :string
#  volume_ml           :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_products_on_reference  (reference) UNIQUE
#
class Product < ActiveRecord::Base
  WINE_COLORS     = %w(red white rose).freeze
  APPELLATIONS    = %w(aop igp vin_de_france).freeze
  PRODUCT_TYPES   = %w(still_wine sparkling_wine spirit other).freeze
  CONTAINER_TYPES = %w(bottle bib case).freeze

  has_many :product_prices, dependent: :destroy

  validates :reference, presence: true, uniqueness: true
  validates :name, presence: true
  validates :color, inclusion: { in: WINE_COLORS }, allow_nil: true
  validates :appellation, inclusion: { in: APPELLATIONS }, allow_nil: true
  validates :product_type, inclusion: { in: PRODUCT_TYPES }, allow_nil: true
  validates :container_type, inclusion: { in: CONTAINER_TYPES }, allow_nil: true
  validates :units_per_container, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def total_volume_ml
    return nil if volume_ml.nil? || units_per_container.nil?

    volume_ml * units_per_container
  end
end
