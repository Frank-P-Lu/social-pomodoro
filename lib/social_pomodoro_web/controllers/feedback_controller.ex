defmodule SocialPomodoroWeb.FeedbackController do
  use SocialPomodoroWeb, :controller

  alias SocialPomodoro.Discord.Webhook

  def create(conn, %{"feedback" => feedback_params}) do
    message = Map.get(feedback_params, "message", "")
    email = Map.get(feedback_params, "email")

    # Send to Discord webhook
    case Webhook.send_feedback(message, email) do
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
