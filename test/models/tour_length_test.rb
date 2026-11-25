require "test_helper"

# A tour plan is at most 10 days; an approved plan may be extended by at most 3 days (still within 10).
class TourLengthTest < ActiveSupport::TestCase
  setup do
    @emp = user("1025"); @l1 = @emp.reporting_manager
    @emp.update!(l2_manager: nil)
    @start = Date.current + 2
  end

  def plan(days)
    @emp.tours.new(send_now: true, from_date: @start, to_date: @start + (days - 1),
      tour_visits_attributes: [ { visit_date: @start, place: "Sehore", planned_activity: "Mtg" } ])
  end

  test "a new plan may be 10 days, not 11" do
    assert plan(10).valid?
    t = plan(11)
    assert_not t.valid?
    assert_match "at most 10 days", t.errors.full_messages.to_sentence
  end

  test "approved 5-day tour can grow to 8 days, not 9" do
    t = plan(5).tap(&:save!)
    t.approve!(by: @l1, remark: "ok")
    assert_equal 5, t.reload.approved_days
    t.to_date = @start + 7   # 8 days
    assert t.valid?, t.errors.full_messages.to_sentence
    t.to_date = @start + 8   # 9 days
    assert_not t.valid?
    assert_match "extended by at most 3 days", t.errors.full_messages.to_sentence
  end

  test "approved 7-day tour can grow to 10, never 11" do
    t = plan(7).tap(&:save!)
    t.approve!(by: @l1, remark: "ok")
    t.to_date = @start + 9
    assert t.valid?
    t.to_date = @start + 10
    assert_not t.valid?
  end

  test "the approved length stays the first one after an extension is approved again" do
    t = plan(5).tap(&:save!)
    t.approve!(by: @l1, remark: "ok")
    t.edit_and_resend!({ to_date: @start + 7 }, by: @emp)
    t.reload.approve!(by: @l1, remark: "ok")
    assert_equal 5, t.reload.approved_days
    t.to_date = @start + 8
    assert_not t.valid?, "cannot keep adding 3 days on every approval"
  end

  test "an old long tour is untouched until its dates change; admin may still correct" do
    t = plan(5).tap(&:save!)
    t.update_columns(to_date: @start + 14)   # 15 days, made before the rule
    t.reload.general_description = "edited text only"
    assert t.valid?
    t.skip_length_rule = true
    t.to_date = @start + 13
    assert t.valid?
  end
end
