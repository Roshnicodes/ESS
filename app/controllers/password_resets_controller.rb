# "Forgot password?" on the login page. The employee types the Employee Code; a one-time link (valid for
# Devise's reset_password_within, 6 hours) goes to the email registered in the Employee List, through the
# same krai mail page every ESS notification uses. The answer never says whether the code exists.
class PasswordResetsController < ApplicationController
  skip_before_action :authenticate_user!
  before_action { redirect_to authenticated_root_path if user_signed_in? }
  rate_limit to: 5, within: 15.minutes, only: :create,
             with: -> { redirect_to new_password_reset_path, alert: "Too many requests. Please try again after some time." }

  SENT = "If this Employee Code has an email in ESS, a password reset link has been sent to it. " \
         "Not received in a few minutes? Contact PD HR.".freeze

  def new; end

  def create
    user = User.active.find_by("LOWER(emp_code) = ?", params[:emp_code].to_s.strip.downcase)
    send_link(user) if user&.email.to_s.include?("@")
    redirect_to new_user_session_path, notice: SENT
  end

  def edit
    @token = params[:token].to_s
    redirect_to new_password_reset_path, alert: "This reset link is invalid or has expired. Please ask for a new one." unless reset_user
  end

  def update
    @token = params[:token].to_s
    user = reset_user
    return redirect_to(new_password_reset_path, alert: "This reset link is invalid or has expired. Please ask for a new one.") unless user

    user.password = params[:password]
    user.password_confirmation = params[:password_confirmation]
    if params[:password].present? && user.save
      user.update_columns(reset_password_token: nil, reset_password_sent_at: nil)
      user.log_activity!(:password_reset, actor: user)
      redirect_to new_user_session_path, notice: "Password changed. Please login with your new password."
    else
      @errors = params[:password].blank? ? [ "Please enter the new password" ] : user.errors.full_messages
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def reset_user
    return if @token.blank?
    user = User.with_reset_password_token(@token)
    user if user&.active? && user.reset_password_period_valid?
  end

  def send_link(user)
    raw = user.send(:set_reset_password_token)
    link = "#{EssMailRelay.app_url}#{edit_password_reset_path(token: raw)}"
    unless EssMailRelay.enabled?
      Rails.logger.warn("Password reset for #{user.emp_code}: mail relay is off (ESS_MAIL_RELAY_URL not set)")
      return
    end
    EssMailJob.perform_later(
      "to_email" => user.email.to_s.strip, "to_name" => user.name.to_s,
      "subject" => "ASA ESS: Reset your password",
      "message" => "We received a request to reset your ESS password. Open the link to set a new password. " \
                   "It works once and expires in #{Devise.reset_password_within.inspect}. If you did not ask for this, ignore this mail.",
      "link" => link, "employee_name" => user.name.to_s, "employee_code" => user.emp_code.to_s,
      "quarter" => "", "month" => "", "reviewer_role" => "", "reviewer_name" => "",
      "action" => "information", "remarks" => "", "mail_type" => "password_reset"
    )
  end
end
