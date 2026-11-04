require "test_helper"

class ClaimsHelperTest < ActionView::TestCase
  test "claim dropdowns list exactly the modes ticked in the Mode of Travel master" do
    na = TravelMode.find_by!(name: "NA")
    na.update!(for_city_travel: true, for_local_travel: true)
    tour_only = TravelMode.create!(name: "Tour Only Mode", for_tour_plan: true, for_city_travel: false, for_local_travel: false, position: 99)

    assert_includes city_travel_modes, na                                  # NA ticked for Claim A → shown
    assert_not_includes city_travel_modes, tour_only                       # Tour Plan tick alone is not Claim A
    assert_includes local_travel_modes, na
    assert_equal city_travel_modes.to_a, TravelMode.active.where(for_city_travel: true).ordered.to_a

    old = TravelMode.create!(name: "Old Mode", for_city_travel: false, position: 98)
    assert_includes modes_with_current(city_travel_modes, old), old         # a saved row keeps its mode
    assert_equal city_travel_modes, modes_with_current(city_travel_modes, nil)
  end
end
