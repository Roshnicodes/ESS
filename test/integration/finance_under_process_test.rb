require "test_helper"

# PD Finance: "Under process & Print" before Project / BLI, then approve later; filters on the claim lists.
class FinanceUnderProcessTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 11, 3, 12)
    @fin = user("FIN001"); @emp = user("1025")
    @claim = finance_pending_claim(@emp, Date.new(2026, 10, 1), 400)
    sign_in @fin
  end

  test "Under process & Print keeps the claim with Finance, prints, and it can be approved later with the coding" do
    get approvals_claim_path(@claim)
    assert_match "Under process &amp; Print", response.body

    patch under_process_approvals_claim_path(@claim)
    assert_redirected_to approvals_claim_path(@claim, print: 1)
    @claim.reload
    assert @claim.finance_pending?
    assert @claim.under_process?
    assert_equal @fin, @claim.under_process_by
    assert_match "Under process", @claim.stage_label
    follow_redirect!
    assert_match 'data-controller="auto-print"', response.body
    assert_match "Under process", response.body                              # badge + stamp

    get approvals_claims_path(type: "local", scope: "under_process")
    assert_match approvals_claim_path(@claim), response.body
    get approvals_claims_path(type: "local")                                   # still pending with Finance
    assert_match approvals_claim_path(@claim), response.body

    coding = finance_mapping
    patch approve_approvals_claim_path(@claim), params: { remark: "ok", project_id: coding.project_id,
      budget_line_item_id: coding.budget_line_item_id, budget_line_item_code_id: coding.budget_line_item_code_id }
    assert @claim.reload.approved?
    assert_not @claim.under_process?
    get approvals_claims_path(type: "local", scope: "under_process")
    assert_no_match approvals_claim_path(@claim), response.body
  end

  test "a return clears Under process" do
    @claim.mark_under_process!(by: @fin)
    patch send_back_approvals_claim_path(@claim), params: { remark: "fix", return_to: "employee" }
    assert_nil @claim.reload.under_process_at
  end

  test "only the reviewing Finance person can mark it" do
    sign_in user("1025")
    patch under_process_approvals_claim_path(@claim)
    assert_nil @claim.reload.under_process_at
  end

  test "From – To date filter on the claim list, and Project / BLI on Payment Advice" do
    get approvals_claims_path(type: "local", from: "2026-10-01", to: "2026-10-31")
    assert_match approvals_claim_path(@claim), response.body
    get approvals_claims_path(type: "local", from: "2026-08-01", to: "2026-08-31")
    assert_no_match approvals_claim_path(@claim), response.body

    coding = finance_mapping
    patch approve_approvals_claim_path(@claim), params: { remark: "ok", project_id: coding.project_id,
      budget_line_item_id: coding.budget_line_item_id, budget_line_item_code_id: coding.budget_line_item_code_id }
    get payment_advices_path(from: "2026-10-01", to: "2026-10-31")
    assert_match "Project · BLI", response.body
    assert_match coding.project.name, response.body
    assert_match coding.budget_line_item.name, response.body
  end

  private

  def finance_pending_claim(employee, month, amount)
    tour = Tour.new(user: employee, tour_type: "local", general_description: "local travel milage claim")
    tour.save!
    tour.update_columns(claim_month: month, from_date: month, to_date: month.end_of_month)
    claim = TourClaim.build_for(tour.reload)
    claim.claim_local_travels.build(travel_date: month, place_from: "Office", place_to: "Field",
                                    travel_mode: mode("Public Transport"), kilometers: 10, amount: amount, purpose: "Visit")
    claim.bank_account = employee.bank_accounts.first
    claim.save!
    claim.update_columns(status: "finance_pending", submitted_at: Time.current, l1_approver_id: user("AM001").id,
                         l1_approved_at: Time.current, l1_approved_by_id: user("AM001").id, finance_approver_id: @fin.id)
    claim.reload
  end
end
