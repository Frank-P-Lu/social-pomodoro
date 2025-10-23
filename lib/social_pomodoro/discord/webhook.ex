defmodule SocialPomodoro.Discord.Webhook do
  @moduledoc """
  Handles sending messages to Discord via webhooks.
  """

  require Logger
  alias SocialPomodoro.Utils

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
    # Only send feedback in production
    if Utils.prod?() do
      webhook_url = Application.get_env(:social_pomodoro, :discord_feedback_webhook_url)
      payload = build_feedback_payload(message, email, username)
      send(webhook_url, payload, "Feedback")
    else
      {:ok, :skipped_non_prod}
    end
  end

  @doc """
  Sends an analytics event to Discord.

  ## Parameters
    - event_type: The type of analytics event
    - data: Map of event data to include

  ## Returns
    - :ok (always returns ok, errors are logged)
  """
  def send_analytics(event_type, data) do
    # Only send analytics in production
    if Utils.prod?() do
      webhook_url = Application.get_env(:social_pomodoro, :discord_analytics_webhook_url)
      payload = build_analytics_payload(event_type, data)
      # Send asynchronously to avoid blocking the caller
      Task.start(fn -> send(webhook_url, payload, "Analytics") end)
      :ok
    else
      :ok
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

  defp build_analytics_payload(event_type, data) do
    formatted_data =
      Enum.map_join(data, "\n", fn {key, value} ->
        "**#{format_key(key)}:** #{format_value(key, value)}"
      end)

    content = """
    **📊 Analytics Event: #{event_type}**
    #{formatted_data}
    _Timestamp: #{DateTime.utc_now() |> DateTime.to_string()}_
    """

    %{
      content: content,
      username: "Social Pomodoro Analytics"
    }
  end

  defp format_key(key) do
    key
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_value(:wait_time_seconds, seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      minutes > 0 and remaining_seconds > 0 ->
        "#{minutes}m #{remaining_seconds}s"

      minutes > 0 ->
        "#{minutes}m"

      true ->
        "#{remaining_seconds}s"
    end
  end

  defp format_value(_key, value), do: inspect(value)

  defp send(url, payload, type) do
    Logger.debug("#{type} webhook URL: #{inspect(url)}")

    if is_nil(url) or url == "" do
      Logger.warning("Discord #{type} webhook URL not configured. Message not sent.")
      {:error, :webhook_not_configured}
    else
      Logger.info("Sending #{type} to Discord")
      Logger.debug("Payload: #{inspect(payload)}")

      case Req.post(url, json: payload) do
        {:ok, %Req.Response{status: status}} when status in 200..299 ->
          Logger.info("#{type} sent to Discord successfully (status: #{status})")
          {:ok, :sent}

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error(
            "Failed to send #{type} to Discord. Status: #{status}, Body: #{inspect(body)}"
          )

          {:error, :request_failed}

        {:error, reason} ->
          Logger.error("Failed to send #{type} to Discord: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
