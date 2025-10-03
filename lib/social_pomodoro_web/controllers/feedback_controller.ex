defmodule SocialPomodoroWeb.FeedbackController do
  use SocialPomodoroWeb, :controller

  alias SocialPomodoro.Discord.Webhook

  def create(conn, params) do
    feedback_params = Map.get(params, "feedback", %{})
    message = Map.get(feedback_params, "message", "")
    email = Map.get(feedback_params, "email")
    username = Map.get(params, "username", "Anonymous")

    # Send to Discord webhook
    case Webhook.send_feedback(message, email, username) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Thank you for your feedback!")
        |> redirect(to: "/")

      {:error, :webhook_not_configured} ->
        conn
        |> put_flash(:info, "Thank you for your feedback! (Webhook not configured)")
        |> redirect(to: "/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to send feedback. Please try again.")
        |> redirect(to: "/")
    end
  end
end
