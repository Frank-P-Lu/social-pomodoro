defmodule SocialPomodoroWeb.FeedbackControllerTest do
  use SocialPomodoroWeb.ConnCase

  describe "POST /api/feedback" do
    test "submits feedback successfully", %{conn: conn} do
      conn =
        post(conn, ~p"/api/feedback", %{
          feedback: %{
            message: "Great app!",
            email: "test@example.com"
          }
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "Thank you for your feedback"
    end

    test "submits feedback without email", %{conn: conn} do
      conn =
        post(conn, ~p"/api/feedback", %{
          feedback: %{
            message: "Great app!"
          }
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "Thank you for your feedback"
    end
  end
end
