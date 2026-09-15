class ProductPrice < ActiveRecord::Base
  belongs_to :product

  validates :grid_code, presence: true, uniqueness: { scope: :product_id }
  validates :amount_ht, numericality: { greater_than_or_equal_to: 0 }
end
