class Product < ActiveRecord::Base
  has_many :product_prices, dependent: :destroy

  validates :reference, presence: true, uniqueness: true
  validates :name, presence: true
end
