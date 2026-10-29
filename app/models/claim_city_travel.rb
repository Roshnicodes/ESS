# A. Travel city to city (start and end at headquarter)
class ClaimCityTravel < ApplicationRecord
  include ClaimLine
  belongs_to :travel_mode

  validates :travel_date, :departure_city, :arrival_city, presence: true
end
