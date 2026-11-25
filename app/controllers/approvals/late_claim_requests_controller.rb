# COO: late local mileage claims (asked after the cutoff day) – approve or reject with a remark.
class Approvals::LateClaimRequestsController < ApplicationController
  before_action -> { redirect_to authenticated_root_path, alert: "Only the COO can see late claim requests." unless LateClaimRequest.decider?(current_user) || current_user.admin? }
  before_action :set_request, only: %i[approve reject]

  def index
    mine = current_user.admin? ? LateClaimRequest.all : LateClaimRequest.where(approver: current_user)
    mine = mine.includes(user: :location, decided_by: [], approver: [])
    @pending = mine.pending.order(:created_at)
    @decided = mine.where.not(status: "pending").order(decided_at: :desc).limit(50)
  end

  def approve
    @request.approve!(by: current_user, remark: params[:remark])
    redirect_to approvals_late_claim_requests_path, notice: "Allowed – #{@request.user.name} can now fill the #{@request.month_label} claim."
  end

  def reject
    @request.reject!(by: current_user, remark: params[:remark])
    redirect_to approvals_late_claim_requests_path, notice: "Not allowed – #{@request.user.name} has been told."
  end

  private

  def set_request
    @request = LateClaimRequest.find(params[:id])
  end
end
