# A. Travel city to city (start and end at headquarter)
class ClaimCityTravel < ApplicationRecord
  include ClaimLine
  belongs_to :travel_mode

  validates :travel_date, presence: true
  validates :departure_city, :arrival_city, presence: true, unless: -> { travel_mode&.not_applicable? }
  validates :ticket_quota, inclusion: { in: TourVisit::QUOTAS.values }
  before_validation { self.ticket_quota = "normal" unless travel_mode&.is_train? }   # quota only for trains

  def tatkal? = ticket_quota == "tatkal"

  private

  # NA = no journey → nothing to claim
  def compute_amount
    self.amount = 0 if travel_mode&.not_applicable?
  end
end
