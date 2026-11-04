class DashboardController < ApplicationController
  def index
    tours = current_user.tours
    @last_tour  = tours.type_tour.newest_first.first
    @last_claim = current_user.tour_claims.includes(:tour).newest_first.first
    @pending_tour_approvals = Tour.pending_for(current_user).count
    @pending_claims = TourClaim.in_queue_of(current_user).count
    today = Date.current
    @on_tour_count = Tour.planned_on(today).count
    @claim_ready = tours.approved.where.missing(:tour_claim).select(&:claimable?).first(4)
  end

  # Dashboard card "Colleagues on tour today" → full list; click an employee for the tour details
  def on_tour
    @day = Date.current
    @tours = Tour.planned_on(@day)
                 .includes(:approver, :l2_approver, { approval_steps: :approver }, { tour_visits: :travel_mode }, user: :location)
                 .order(Arel.sql("CASE WHEN tours.status = 'approved' THEN 0 ELSE 1 END"), :from_date).to_a
  end
end
