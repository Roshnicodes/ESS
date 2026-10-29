class ApplicationController < ActionController::Base

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :set_current

  rescue_from CanCan::AccessDenied do |e|
    redirect_back fallback_location: root_path, alert: e.message.presence || "You are not authorised for this action."
  end

  rescue_from Workflow::Error do |e|
    redirect_back fallback_location: root_path, alert: e.message
  end

  rescue_from ActiveRecord::StaleObjectError do
    redirect_back fallback_location: root_path, alert: "This record was changed by someone else. Please reload and try again."
  end

  private

  def set_current
    Current.user = current_user
    Current.ip_address = request.remote_ip
  end
end
