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

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def send_feedback(message, email \\ nil) do
    webhook_url = Application.get_env(:social_pomodoro, :discord_webhook_url)

    if is_nil(webhook_url) or webhook_url == "" do
      Logger.warning("Discord webhook URL not configured. Feedback not sent.")
      {:error, :webhook_not_configured}
    else
      payload = build_feedback_payload(message, email)
      send_webhook(webhook_url, payload)
    end
  end

  defp build_feedback_payload(message, email) do
    content =
      if email do
        """
        **New Feedback Received**
        
        **Message:** #{message}
        
        **Reply to:** #{email}
        """
      else
        """
        **New Feedback Received**
        
        **Message:** #{message}
        
        **Reply to:** _No email provided_
        """
      end

    %{
      content: content,
      username: "Social Pomodoro Feedback"
    }
  end

  defp send_webhook(url, payload) do
    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(payload)

    case :httpc.request(:post, {String.to_charlist(url), headers, ~c"application/json", body}, [], []) do
      {:ok, {{_, status_code, _}, _headers, _body}} when status_code in 200..299 ->
        Logger.info("Feedback sent to Discord successfully")
        {:ok, :sent}

      {:ok, {{_, status_code, _}, _headers, body}} ->
        Logger.error("Failed to send feedback to Discord. Status: #{status_code}, Body: #{body}")
        {:error, :request_failed}

      {:error, reason} ->
        Logger.error("Failed to send feedback to Discord: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
