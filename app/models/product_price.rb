# == Schema Information
#
# Table name: product_prices
#
#  id         :bigint           not null, primary key
#  amount_ht  :decimal(10, 2)   not null
#  grid_code  :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  product_id :bigint           not null
#
# Indexes
#
#  index_product_prices_on_product_id                (product_id)
#  index_product_prices_on_product_id_and_grid_code  (product_id,grid_code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (product_id => products.id)
#
class ProductPrice < ActiveRecord::Base
  belongs_to :product

  validates :grid_code, presence: true, uniqueness: { scope: :product_id }
  validates :amount_ht, numericality: { greater_than_or_equal_to: 0 }
end
