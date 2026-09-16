# == Schema Information
#
# Table name: products
#
#  id         :bigint           not null, primary key
#  color      :string
#  name       :string           not null
#  reference  :string           not null
#  stock      :integer
#  vat_rate   :decimal(5, 2)
#  vintage    :string
#  volume_ml  :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_products_on_reference  (reference) UNIQUE
#
class Product < ActiveRecord::Base
  has_many :product_prices, dependent: :destroy

  validates :reference, presence: true, uniqueness: true
  validates :name, presence: true
end
