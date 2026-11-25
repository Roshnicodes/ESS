require "test_helper"

# Local mileage after the cutoff day (5): the employee asks PD HR; once PD HR approves the month opens
# again for that employee, and the claim goes L1 → COO (last approver) → Finance.
class LateClaimRequestTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 11, 20, 12)   # October closed on 05-Nov
    @emp = user("1025"); @hr = user("HR001"); @l1 = @emp.reporting_manager
    @emp.update!(l2_manager: nil)
    @coo = User.create!(emp_code: "COO1", name: "Chief Ops", designation: "COO", password: "123456")
    @oct = Date.new(2026, 10, 1)
  end

  test "October is closed after the cutoff; the employee asks PD HR" do
    sign_in @emp
    get tours_path(type: "local")
    assert_match "Missed the cutoff for Oct-2026? Ask PD HR", response.body

    post late_claim_requests_path, params: { reason: "" }
    assert_equal 0, LateClaimRequest.count, "reason is required"

    post late_claim_requests_path, params: { reason: "Was on leave till 10-Nov" }
    r = LateClaimRequest.last
    assert r.pending?
    assert_equal [ @emp, @oct ], [ r.user, r.claim_month ]
    assert Notification.exists?(user: @hr, notifiable: r, kind: "late_claim_pending")
    refute Notification.exists?(user: @coo, notifiable: r), "the request itself is PD HR's only"
    follow_redirect!
    assert_match "waiting for <b>PD HR</b>", response.body

    post late_claim_requests_path, params: { reason: "again" }
    assert_equal 1, LateClaimRequest.count, "only one open request per month"

    get new_local_mileage_path(month: "2026-10")   # not approved yet → normal (November) form
    assert_match "Nov-2026", response.body
  end

  test "PD HR approves; the claim goes L1 → COO → Finance" do
    r = LateClaimRequest.new(user: @emp, claim_month: @oct, reason: "On leave").ask!

    sign_in @coo   # COO does not decide the request
    get approvals_late_claim_requests_path
    assert_redirected_to authenticated_root_path

    sign_in @hr
    get approvals_late_claim_requests_path
    assert_match @emp.name, response.body
    patch approve_approvals_late_claim_request_path(r), params: { remark: "" }
    assert r.reload.pending?, "remark is required"
    patch approve_approvals_late_claim_request_path(r), params: { remark: "Leave verified" }
    assert r.reload.approved?
    assert Notification.exists?(user: @emp, notifiable: r, kind: "late_claim_approved")

    sign_in @emp
    get tours_path(type: "local")
    assert_match "allowed your late local mileage claim", response.body
    get new_local_mileage_path(month: "2026-10")
    assert_response :success
    assert_match "Oct-2026", response.body
    assert_match "Late claim allowed by PD HR", response.body

    post local_mileage_path(month: "2026-10"), params: { commit_action: "submit", tour_claim: { helmet_declaration: "1", bank_account_id: @emp.bank_accounts.first.id,
      claim_local_travels_attributes: { "0" => { travel_date: "2026-10-15", place_from: "Office", place_to: "Village", travel_mode_id: mode("Public Transport").id, kilometers: 10, amount: 100, purpose: "Visit" } } } }
    claim = @emp.tours.type_local.find_by(claim_month: @oct)&.tour_claim
    assert claim&.submitted?, claim&.errors&.full_messages.inspect
    assert_equal [ @coo.id ], claim.approval_steps.map(&:approver_id)
    assert_match "Late claim", claim.approval_steps.last.reason

    claim.forward!(by: @l1, remark: "ok")
    assert claim.reload.extra_pending?
    assert_equal @coo, claim.extra_approver, "after L1 the COO approves last"
    claim.forward!(by: @coo, remark: "ok")
    assert claim.reload.finance_pending?
  end

  test "an on-time local claim does not go to the COO" do
    travel_to Time.zone.local(2026, 11, 3, 12)
    tour = @emp.tours.create!(tour_type: "local", general_description: "local")
    claim = TourClaim.build_for(tour)
    claim.claim_local_travels.build(travel_date: tour.from_date, place_from: "A", place_to: "B", travel_mode: mode("Public Transport"), kilometers: 10, amount: 100, purpose: "x")
    claim.bank_account = @emp.bank_accounts.first
    claim.helmet_declaration = true
    claim.save!
    claim.submit!(by: @emp)
    assert_empty claim.approval_steps
  end

  test "PD HR rejects: October stays closed and the employee sees why" do
    r = LateClaimRequest.new(user: @emp, claim_month: @oct, reason: "Forgot").ask!
    sign_in @hr
    patch reject_approvals_late_claim_request_path(r), params: { remark: "No reason given" }
    assert r.reload.rejected?
    assert LocalMileagePeriod.new(@emp).closed?(@oct)
    sign_in @emp
    get tours_path(type: "local")
    assert_match "No reason given", response.body
  end

  test "others cannot see or decide" do
    r = LateClaimRequest.new(user: @emp, claim_month: @oct, reason: "Forgot").ask!
    sign_in user("AM001")
    get approvals_late_claim_requests_path
    assert_redirected_to authenticated_root_path
    patch approve_approvals_late_claim_request_path(r), params: { remark: "x" }
    assert r.reload.pending?
  end

  test "before the cutoff nothing changes: the month is open without asking" do
    travel_to Time.zone.local(2026, 11, 4, 12)
    period = LocalMileagePeriod.new(@emp)
    assert_equal @oct, period.month
    refute period.closed?(@oct)
    assert_not LateClaimRequest.new(user: @emp, claim_month: @oct, reason: "x").valid?, "an open month needs no request"
  end
end
