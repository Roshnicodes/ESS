# PD HR: late local mileage claims (asked after the cutoff day) – approve or reject with a remark.
# Approved → the employee can fill that month; the claim then has the COO as its last approver.
class Approvals::LateClaimRequestsController < ApplicationController
  before_action -> { redirect_to authenticated_root_path, alert: "Only PD HR can see late claim requests." unless LateClaimRequest.decider?(current_user) || current_user.admin? }
  before_action :set_request, only: %i[approve reject]

  def index
    all = LateClaimRequest.includes(:decided_by, user: :location)
    @pending = all.pending.order(:created_at)
    @decided = all.where.not(status: "pending").order(decided_at: :desc).limit(50)
  end

  def approve
    @request.approve!(by: current_user, remark: params[:remark])
    redirect_to approvals_late_claim_requests_path, notice: "Allowed – #{@request.user.name} can now fill the #{@request.month_label} claim (COO gives its last approval)."
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
