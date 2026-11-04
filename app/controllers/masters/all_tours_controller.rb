# Admin: every tour of every employee – view, edit, delete.
class Masters::AllToursController < ApplicationController
  before_action { raise CanCan::AccessDenied, "Only admin" unless current_user.admin? }

  # Pending (tour or its claim waiting with someone) first, then everything else, and plans / claims that are
  # only saved ("Prepared", never sent) last; newest first inside each group.
  CLAIM_STATUS = "(SELECT c.status FROM tour_claims c WHERE c.tour_id = tours.id LIMIT 1)".freeze
  LIST_ORDER = <<~SQL.squish.freeze
    CASE
      WHEN tours.status IN ('submitted', 'l1_approved', 'l2_approved') THEN 0
      WHEN #{CLAIM_STATUS} IN ('submitted', 'l1_approved', 'extra_pending', 'finance_pending', 'finance_query') THEN 0
      WHEN tours.status = 'draft' THEN 2
      WHEN tours.tour_type = 'local' AND COALESCE(#{CLAIM_STATUS}, 'draft') = 'draft' THEN 2
      ELSE 1
    END
  SQL

  def index
    @tours = Tour.includes(:user, :approver, :l2_approver, :tour_claim).order(Arel.sql(LIST_ORDER), created_at: :desc)
    if params[:q].present?
      q = "%#{Tour.sanitize_sql_like(params[:q].strip)}%"
      @tours = @tours.joins(:user).where("users.name ILIKE :q OR users.emp_code ILIKE :q", q: q)
    end
    @tours = @tours.where(status: params[:status]) if params[:status].present?
    @tours = @tours.where(tour_type: params[:type]) if params[:type].present?
    @tours = @tours.page(params[:page]).per(30)
  end
end
