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
