defmodule SocialPomodoro.TelemetryHandler do
  @moduledoc """
  Handles telemetry events and sends analytics to Discord webhook.

  All webhook sending is done asynchronously to prevent blocking the caller
  (typically a GenServer handling room state). This ensures that HTTP requests
  don't cause timeouts in critical code paths.
  """

  require Logger

  @doc """
  Handles telemetry events and sends them to Discord webhook for analytics.

  Note: This function returns immediately. Webhook requests are sent asynchronously
  in a separate process to avoid blocking.
  """
  def handle_event([:pomodoro, :room, :created], _measurements, metadata, _config) do
    send_analytics("Room Created", %{
      room_name: metadata[:room_name],
      creator_user_id: metadata[:user_id],
      duration_minutes: metadata[:duration_minutes]
    })
  end

  def handle_event([:pomodoro, :session, :started], _measurements, metadata, _config) do
    send_analytics("Session Started", %{
      room_name: metadata[:room_name],
      participant_user_ids: metadata[:participant_user_ids],
      participant_count: metadata[:participant_count],
      wait_time_seconds: metadata[:wait_time_seconds]
    })
  end

  def handle_event([:pomodoro, :session, :restarted], _measurements, metadata, _config) do
    send_analytics("Session Restarted", %{
      room_name: metadata[:room_name],
      participant_user_ids: metadata[:participant_user_ids],
      participant_count: metadata[:participant_count]
    })
  end

  def handle_event([:pomodoro, :session, :completed], _measurements, metadata, _config) do
    send_analytics("Session Completed", %{
      room_name: metadata[:room_name],
      participant_count: metadata[:participant_count],
      duration_minutes: metadata[:duration_minutes]
    })
  end

  defp send_analytics(event_type, data) do
    webhook_url = Application.get_env(:social_pomodoro, :discord_analytics_webhook_url)

    Logger.debug("Analytics webhook URL: #{inspect(webhook_url)}")

    if is_nil(webhook_url) or webhook_url == "" do
      Logger.warning(
        "Discord analytics webhook URL not configured. Analytics not sent for: #{event_type}"
      )

      :ok
    else
      Logger.info("Sending analytics event to Discord: #{event_type}")
      payload = build_analytics_payload(event_type, data)
      # Send webhook asynchronously to avoid blocking the caller
      Task.start(fn -> send_webhook(webhook_url, payload) end)
      :ok
    end
  end

  defp build_analytics_payload(event_type, data) do
    formatted_data =
      data
      |> Enum.map(fn {key, value} -> "**#{format_key(key)}:** #{format_value(key, value)}" end)
      |> Enum.join("\n")

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
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
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

  defp send_webhook(url, payload) do
    Logger.debug("Sending webhook request to: #{url}")
    Logger.debug("Payload: #{inspect(payload)}")

    case Req.post(url, json: payload) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        Logger.info("Analytics sent to Discord successfully (status: #{status})")
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error(
          "Failed to send analytics to Discord. Status: #{status}, Body: #{inspect(body)}"
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to send analytics to Discord: #{inspect(reason)}")
        :ok
    end
  end
end
