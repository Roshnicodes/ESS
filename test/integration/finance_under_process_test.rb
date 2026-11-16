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

  test "NA project: Finance can approve a claim that belongs to no project (NA / NA / NA)" do
    get approvals_claim_path(@claim)
    assert_match "NA – no project", response.body
    assert_match "Local Mileage Claim", response.body                     # page named after the claim type
    na = ProjectBudgetLineItem.ensure_na!
    patch approve_approvals_claim_path(@claim), params: { remark: "ok", project_id: na.project_id,
      budget_line_item_id: na.budget_line_item_id, budget_line_item_code_id: na.budget_line_item_code_id }
    assert @claim.reload.approved?
    assert_equal %w[NA NA NA], [ @claim.project.name, @claim.budget_line_item.name, @claim.budget_line_item_code.name ]
    assert_equal na, ProjectBudgetLineItem.ensure_na!                      # never duplicated
  end

  test "summary: Pay to after the travel details and Location under the name" do
    get approvals_claim_path(@claim)
    body = response.body
    assert body.index("Sub total") < body.index("Pay to")                 # bank after the details, screen and paper
    assert_equal 1, body.scan(">Pay to<").size
    assert_match(/<b>#{Regexp.escape(@emp.name)}<\/b>.{0,400}>Location</m, body)   # location on the line under the name
  end

  test "employee can view / print a claim that is only saved, without opening Edit" do
    @claim.update_columns(status: "draft", submitted_at: nil)
    sign_in @emp
    get tours_path(type: "local")
    assert_match %(href="#{tour_claim_path(@claim.tour)}"), response.body
    get tour_claim_path(@claim.tour)
    assert_response :success
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
