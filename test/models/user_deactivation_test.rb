require "test_helper"

# An employee who is still someone's L-1 / L-2 / Finance approver cannot be deactivated
# until HR sets a new approver for those employees.
class UserDeactivationTest < ActiveSupport::TestCase
  setup do
    @boss = User.create!(emp_code: "BOSSD1", name: "Boss D", password: "123456")
    @emp  = User.create!(emp_code: "EMPD1", name: "Emp D", password: "123456", l2_manager: @boss)
  end

  test "approver cannot be deactivated while assigned" do
    refute @boss.update(active: false)
    assert_match(/approval authority for 1 active employee: Emp D \(EMPD1\) – L-2/, @boss.errors.full_messages.join)
    assert @boss.reload.active?
  end

  test "approver can be deactivated once a new approver is set" do
    @emp.update!(l2_manager: nil)
    assert @boss.update(active: false)
  end

  test "inactive dependents do not block, and other edits still save" do
    assert @boss.update(mobile: "9999999999")
    @emp.update!(active: false)
    assert @boss.update(active: false)
  end
end
