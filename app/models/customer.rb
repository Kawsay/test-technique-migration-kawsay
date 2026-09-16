# == Schema Information
#
# Table name: customers
#
#  id                    :bigint           not null, primary key
#  active                :boolean          default(TRUE), not null
#  address1              :string
#  city                  :string
#  company_name          :string
#  country_code          :string(2)
#  creation_date         :date
#  customer_category     :string
#  email                 :string
#  excise_number         :string
#  first_name            :string
#  kind                  :string           default("customer"), not null
#  last_name             :string
#  mobile                :string
#  phone                 :string
#  price_grid_code       :string
#  reference             :string           not null
#  shipping_address1     :string
#  shipping_city         :string
#  shipping_company_name :string
#  shipping_country_code :string(2)
#  shipping_first_name   :string
#  shipping_last_name    :string
#  shipping_phone        :string
#  shipping_zip          :string
#  use_billing_address   :boolean          default(TRUE), not null
#  vat_number            :string
#  zip                   :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_customers_on_price_grid_code  (price_grid_code)
#  index_customers_on_reference        (reference) UNIQUE
#  index_customers_on_vat_number       (vat_number)
#
class Customer < ActiveRecord::Base
  KINDS = %w[customer supplier prospect].freeze

  validates :reference, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validate  :name_present

  private

  def name_present
    return if company_name.present? || first_name.present? || last_name.present?

    errors.add(:base, "ni raison sociale, ni nom, ni prénom")
  end
end
