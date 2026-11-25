# Employee: after the cutoff day, ask the COO to allow last month's local mileage claim.
class LateClaimRequestsController < ApplicationController
  def create
    period = LocalMileagePeriod.new(current_user)
    request = LateClaimRequest.new(user: current_user, claim_month: period.late_month, reason: params[:reason].to_s.strip)
    if request.valid?
      request.ask!
      redirect_to tours_path(type: "local"), notice: "Request sent to COO – #{request.approver.name}. You can fill the #{request.month_label} claim once it is approved."
    else
      redirect_to tours_path(type: "local"), alert: request.errors.full_messages.to_sentence
    end
  end
end
