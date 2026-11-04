require "test_helper"

class PasswordResetTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @emp = user("1025")
    @emp.update_columns(email: "emp1025@example.org")
    @old_url = ENV["ESS_MAIL_RELAY_URL"]
    ENV["ESS_MAIL_RELAY_URL"] = "https://krai.example.org/ess_notification.aspx"
  end

  teardown { ENV["ESS_MAIL_RELAY_URL"] = @old_url }

  test "login page links to forgot password; the mailed link sets a new password once" do
    get new_user_session_path
    assert_match new_password_reset_path, response.body

    assert_enqueued_with(job: EssMailJob) do
      post password_reset_path, params: { emp_code: "1025" }
    end
    assert_redirected_to new_user_session_path
    link = enqueued_jobs.last[:args].first["link"]
    assert_equal "emp1025@example.org", enqueued_jobs.last[:args].first["to_email"]
    token = Rack::Utils.parse_query(URI(link).query)["token"]

    get edit_password_reset_path(token: token)
    assert_response :success
    patch password_reset_path, params: { token: token, password: "NewPass@1", password_confirmation: "NewPass@2" }
    assert_response :unprocessable_entity                                  # confirmation must match
    patch password_reset_path, params: { token: token, password: "NewPass@1", password_confirmation: "NewPass@1" }
    assert_redirected_to new_user_session_path
    assert @emp.reload.valid_password?("NewPass@1")

    get edit_password_reset_path(token: token)                             # link works only once
    assert_redirected_to new_password_reset_path
  end

  test "unknown code gets the same answer and no mail" do
    assert_no_enqueued_jobs(only: EssMailJob) do
      post password_reset_path, params: { emp_code: "NOPE-999" }
    end
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_match "If this Employee Code has an email", response.body
  end

  test "expired link is refused" do
    raw = @emp.send(:set_reset_password_token)
    @emp.update_columns(reset_password_sent_at: 7.hours.ago)
    get edit_password_reset_path(token: raw)
    assert_redirected_to new_password_reset_path
  end
end
