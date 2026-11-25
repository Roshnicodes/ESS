# Decides which month an employee may raise a Local Mileage claim for, and how long
# a claim for a month may still be SENT.
#
# Rule (cutoff day C, default 5, editable by PD HR globally or per employee):
#   on or before day C of a month -> previous month is still shown (late claims allowed)
#   after day C                   -> current month is shown
#
# e.g. C = 5:  03-Nov -> Oct-2026,  06-Nov -> Nov-2026
#
# The same day closes the month for good: a claim of month M must reach L1 on or
# before day C of the next month. An October claim saved but never sent is therefore
# dead from 06-Nov (C = 5) – the employee is told so instead of silently failing.
#
# Late claim: after the cutoff the employee may ask PD HR (LateClaimRequest) for the month that
# just closed; once PD HR approves, that month is open again for that employee (the claim then has
# the COO as its last approver).
class LocalMileagePeriod
  attr_reader :user, :today

  def initialize(user, today: Date.current)
    @user  = user
    @today = today
  end

  def cutoff_day
    @cutoff_day ||= ClaimCutoffRule.cutoff_day_for(user)
  end

  def month
    today.day > cutoff_day ? today.beginning_of_month : today.prev_month.beginning_of_month
  end

  def from_date = month
  def to_date   = month.end_of_month
  def label     = month.strftime("%b-%Y")

  # Last date on which a claim for `claim_month` may be sent for approval:
  # the cutoff day of the following month (clamped, so day 31 never overflows).
  def deadline_for(claim_month)
    nxt = claim_month.to_date.beginning_of_month.next_month
    nxt + [ cutoff_day, nxt.end_of_month.day ].min - 1
  end

  # The cutoff of that month has passed.
  def past_deadline?(claim_month) = today > deadline_for(claim_month)

  # True once that month can no longer be sent (unless the COO allowed a late claim).
  def closed?(claim_month) = past_deadline?(claim_month) && !late_approved?(claim_month)

  # The month a late claim may be asked for: the one just before the month now shown.
  def late_month = month.prev_month

  def late_approved?(claim_month) = LateClaimRequest.approved_for?(user, claim_month)

  # Month to use for a new local mileage form: the late month when asked for and allowed, else the normal one.
  def claim_month_for(requested)
    wanted = (Date.strptime(requested.to_s, "%Y-%m") rescue nil)
    wanted && wanted == late_month && late_approved?(wanted) ? wanted : month
  end

  # Message shown on the form and returned as a validation error.
  def closed_message(claim_month)
    "Local mileage for #{claim_month.to_date.strftime('%b-%Y')} can no longer be filled or sent – " \
    "the last date was #{deadline_for(claim_month).strftime('%d/%m/%Y')} (cutoff day #{cutoff_day} of the next month). " \
    "Ask PD HR for a late claim from Local Mileage History."
  end

  def already_claimed?
    return @already_claimed if defined?(@already_claimed)
    @already_claimed = user.tours.type_local.live.exists?(claim_month: month)
  end
end
