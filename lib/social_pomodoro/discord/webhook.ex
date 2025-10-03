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
    webhook_url = Application.get_env(:social_pomodoro, :discord_webhook_url)

    if is_nil(webhook_url) or webhook_url == "" do
      Logger.warning("Discord webhook URL not configured. Feedback not sent.")
      {:error, :webhook_not_configured}
    else
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
    headers = [{~c"Content-Type", ~c"application/json"}]
    body = Jason.encode!(payload)

    case :httpc.request(
           :post,
           {String.to_charlist(url), headers, ~c"application/json", String.to_charlist(body)},
           [],
           []
         ) do
      {:ok, {{_, status_code, _}, _headers, _body}} when status_code in 200..299 ->
        Logger.info("Feedback sent to Discord successfully")
        {:ok, :sent}

      {:ok, {{_, status_code, _}, _headers, response_body}} ->
        Logger.error(
          "Failed to send feedback to Discord. Status: #{status_code}, Body: #{response_body}"
        )

        {:error, :request_failed}

      {:error, reason} ->
        Logger.error("Failed to send feedback to Discord: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
