# Local mileage after the cutoff day: the employee writes why the claim is late and asks PD HR.
# Any PD HR approves (with a remark) → that month opens again for that employee only; rejected → stays
# closed. The claim then sent goes L1 → L2 → … with the COO as the last approver before Finance
# (see TourClaim#extra_needs).
class LateClaimRequest < ApplicationRecord
  include Auditable

  STATUSES = %w[pending approved rejected].index_by(&:itself).freeze
  COO_DESIGNATION = "COO"

  enum :status, STATUSES, validate: true

  belongs_to :user
  belongs_to :approver,   class_name: "User", optional: true   # not used: any PD HR decides
  belongs_to :decided_by, class_name: "User", optional: true

  validates :claim_month, presence: true
  validates :reason, presence: { message: "– write why the claim is late" }, length: { maximum: 2000 }
  validates :decision_remark, length: { maximum: 2000 }
  validate  :one_open_request, on: :create
  validate  :month_is_closed, on: :create

  before_validation { self.claim_month = claim_month&.beginning_of_month }

  scope :open_or_approved, -> { where(status: %w[pending approved]) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # The COO (designation "COO") is the last approver of a late claim.
  def self.coo = User.where(active: true).where("UPPER(TRIM(designation)) = ?", COO_DESIGNATION).order(:id).first
  def self.hr_people = User.where(active: true, role: "pd_hr").to_a
  def self.decider?(user) = user.present? && user.pd_hr?

  def self.approved_for?(user, month)
    user && month && approved.exists?(user_id: user.id, claim_month: month.to_date.beginning_of_month)
  end

  def month_label = claim_month.strftime("%b-%Y")

  def decidable_by?(by) = pending? && by.present? && by.pd_hr? && by.id != user_id

  def ask!
    transaction do
      save!
      log_activity!(:late_claim_requested, actor: user, to: status, remark: reason, details: { month: month_label })
      self.class.hr_people.each do |hr|
        push hr, user, :late_claim_pending, "Late local mileage claim – your approval (PD HR)",
             "#{user.name} (#{user.emp_code}) wants to claim local mileage for #{month_label} after the cutoff", reason
      end
    end
    self
  end

  def approve!(by:, remark:) = decide!(:approved, by, remark)
  def reject!(by:, remark:)  = decide!(:rejected, by, remark)

  private

  def decide!(to, by, remark)
    raise Workflow::RemarkRequired, "Please write a remark before Approve / Reject." if remark.to_s.strip.blank?
    with_lock do
      raise Workflow::NotAllowed, "This request is not pending with you" unless decidable_by?(by)
      from = status
      update!(status: to.to_s, decided_by: by, decided_at: Time.current, decision_remark: remark.strip)
      log_activity!(:"late_claim_#{to}", actor: by, from: from, to: status, remark: remark, details: { month: month_label })
      if approved?
        push user, by, :late_claim_approved, "Late claim allowed – fill #{month_label} local mileage",
             "PD HR #{by.name} allowed your #{month_label} local mileage claim (COO gives the last approval of the claim)", remark
      else
        push user, by, :late_claim_rejected, "Late claim not allowed for #{month_label}",
             "PD HR #{by.name} did not allow your #{month_label} local mileage claim", remark
      end
    end
    self
  end

  def push(to, actor, kind, title, body, remark)
    return if to.nil? || to == actor
    body = "#{body} – “#{remark.to_s.strip}”" if remark.present?
    url = to == user ? "/tours?type=local" : "/approvals/late_claim_requests"
    Notification.create!(user: to, actor: actor, notifiable: self, kind: kind.to_s, title: title.first(200), body: body, url: url)
  end

  def one_open_request
    return unless user && claim_month
    if self.class.open_or_approved.exists?(user_id: user_id, claim_month: claim_month)
      errors.add(:base, "A late claim request for #{month_label} is already pending or approved")
    end
  end

  def month_is_closed
    return unless user && claim_month
    period = LocalMileagePeriod.new(user)
    errors.add(:base, "#{month_label} is still open – no approval needed") unless period.past_deadline?(claim_month)
    errors.add(:base, "Late claim can be asked only for #{period.late_month.strftime('%b-%Y')}") unless claim_month == period.late_month
    errors.add(:base, "No PD HR found to approve the request") if self.class.hr_people.empty?
  end
end
