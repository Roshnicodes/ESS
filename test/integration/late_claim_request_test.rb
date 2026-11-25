require "test_helper"

# Local mileage after the cutoff day (5): the employee asks the COO; once approved the month opens again.
class LateClaimRequestTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 11, 20, 12)   # October closed on 05-Nov
    @emp = user("1025")
    @coo = User.create!(emp_code: "COO1", name: "Chief Ops", designation: "COO", password: "123456")
    @oct = Date.new(2026, 10, 1)
  end

  test "October is closed after the cutoff; the employee asks the COO" do
    sign_in @emp
    get tours_path(type: "local")
    assert_match "Missed the cutoff for Oct-2026", response.body

    post late_claim_requests_path, params: { reason: "" }
    assert_equal 0, LateClaimRequest.count, "reason is required"

    post late_claim_requests_path, params: { reason: "Was on leave till 10-Nov" }
    r = LateClaimRequest.last
    assert r.pending?
    assert_equal [ @emp, @coo, @oct ], [ r.user, r.approver, r.claim_month ]
    assert Notification.exists?(user: @coo, notifiable: r, kind: "late_claim_pending")
    follow_redirect!
    assert_match "waiting for COO", response.body

    post late_claim_requests_path, params: { reason: "again" }
    assert_equal 1, LateClaimRequest.count, "only one open request per month"

    get new_local_mileage_path(month: "2026-10")   # not approved yet → normal (November) form
    assert_match "Nov-2026", response.body
  end

  test "COO approves with a remark; the employee fills and sends October to L1" do
    r = LateClaimRequest.new(user: @emp, claim_month: @oct, reason: "On leave").ask!
    refute LocalMileagePeriod.new(@emp).late_approved?(@oct)

    sign_in @coo
    get approvals_late_claim_requests_path
    assert_match @emp.name, response.body
    patch approve_approvals_late_claim_request_path(r), params: { remark: "" }
    assert r.reload.pending?, "remark is required"
    patch approve_approvals_late_claim_request_path(r), params: { remark: "OK, genuine" }
    assert r.reload.approved?
    assert Notification.exists?(user: @emp, notifiable: r, kind: "late_claim_approved")

    sign_in @emp
    get tours_path(type: "local")
    assert_match "allowed your late local mileage claim", response.body
    get new_local_mileage_path(month: "2026-10")
    assert_response :success
    assert_match "Oct-2026", response.body
    assert_match "Late claim allowed by the COO", response.body

    post local_mileage_path(month: "2026-10"), params: { commit_action: "submit", tour_claim: { helmet_declaration: "1", bank_account_id: @emp.bank_accounts.first.id,
      claim_local_travels_attributes: { "0" => { travel_date: "2026-10-15", place_from: "Office", place_to: "Village", travel_mode_id: mode("Public Transport").id, kilometers: 10, amount: 100, purpose: "Visit" } } } }
    tour = @emp.tours.type_local.find_by(claim_month: @oct)
    assert tour, flash.to_h.inspect
    assert tour.tour_claim.submitted?, tour.tour_claim.errors.full_messages.inspect
  end

  test "COO rejects: October stays closed and the employee sees why" do
    r = LateClaimRequest.new(user: @emp, claim_month: @oct, reason: "Forgot").ask!
    sign_in @coo
    patch reject_approvals_late_claim_request_path(r), params: { remark: "Too late" }
    assert r.reload.rejected?
    assert LocalMileagePeriod.new(@emp).closed?(@oct)
    sign_in @emp
    get tours_path(type: "local")
    assert_match "Too late", response.body
  end

  test "someone else cannot decide, and the page is only for the COO" do
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
