defmodule SocialPomodoro.Discord.Webhook do
  @moduledoc """
  Handles sending messages to Discord via webhooks.
  """

  require Logger

  @doc """
  Sends a feedback message to Discord.

  ## Parameters
    - message: The feedback message text
    - email: Optional email address for reply (can be nil)
    - username: Optional username of the person submitting feedback (can be nil)

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def send_feedback(message, email \\ nil, username \\ nil) do
    webhook_url = Application.get_env(:social_pomodoro, :discord_feedback_webhook_url)

    Logger.debug("Feedback webhook URL: #{inspect(webhook_url)}")

    if is_nil(webhook_url) or webhook_url == "" do
      Logger.warning("Discord feedback webhook URL not configured. Feedback not sent.")
      {:error, :webhook_not_configured}
    else
      Logger.info("Sending feedback to Discord")
      payload = build_feedback_payload(message, email, username)
      send_webhook(webhook_url, payload)
    end
  end

  defp build_feedback_payload(message, email, username) do
    user_info = if username, do: "**From:** #{username}\n", else: ""

    email_info =
      if email && String.trim(email) != "" do
        "**Reply to:** #{email}"
      else
        "**Reply to:** _No email provided_"
      end

    content = """
    #{user_info}**Message:** #{message}
    #{email_info}
    """

    %{
      content: content,
      username: "Social Pomodoro Feedback"
    }
  end

  defp send_webhook(url, payload) do
    case Req.post(url, json: payload) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        Logger.info("Feedback sent to Discord successfully (status: #{status})")
        {:ok, :sent}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error(
          "Failed to send feedback to Discord. Status: #{status}, Body: #{inspect(body)}"
        )

        {:error, :request_failed}

      {:error, reason} ->
        Logger.error("Failed to send feedback to Discord: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
