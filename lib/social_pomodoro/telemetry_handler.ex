defmodule SocialPomodoro.TelemetryHandler do
  @moduledoc """
  Handles telemetry events and sends analytics to Discord webhook.
  """

  require Logger

  @doc """
  Handles telemetry events and sends them to Discord webhook for analytics.
  """
  def handle_event([:pomodoro, :room, :created], _measurements, metadata, _config) do
    send_analytics("Room Created", %{
      room_id: metadata[:room_id],
      creator_user_id: metadata[:user_id],
      duration_minutes: metadata[:duration_minutes]
    })
  end

  def handle_event([:pomodoro, :session, :started], _measurements, metadata, _config) do
    send_analytics("Session Started", %{
      room_id: metadata[:room_id],
      participant_user_ids: metadata[:participant_user_ids],
      participant_count: metadata[:participant_count],
      wait_time_seconds: metadata[:wait_time_seconds]
    })
  end

  def handle_event([:pomodoro, :session, :restarted], _measurements, metadata, _config) do
    send_analytics("Session Restarted", %{
      room_id: metadata[:room_id],
      participant_user_ids: metadata[:participant_user_ids],
      participant_count: metadata[:participant_count]
    })
  end

  def handle_event([:pomodoro, :session, :completed], _measurements, metadata, _config) do
    send_analytics("Session Completed", %{
      room_id: metadata[:room_id],
      participant_count: metadata[:participant_count],
      duration_minutes: metadata[:duration_minutes]
    })
  end

  defp send_analytics(event_type, data) do
    webhook_url = Application.get_env(:social_pomodoro, :discord_webhook_url)

    if is_nil(webhook_url) or webhook_url == "" do
      Logger.debug("Discord webhook URL not configured. Analytics not sent for: #{event_type}")
      :ok
    else
      payload = build_analytics_payload(event_type, data)
      # Send webhook asynchronously to avoid blocking the caller
      Task.start(fn -> send_webhook(webhook_url, payload) end)
      :ok
    end
  end

  defp build_analytics_payload(event_type, data) do
    formatted_data =
      data
      |> Enum.map(fn {key, value} -> "**#{format_key(key)}:** #{inspect(value)}" end)
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
        Logger.debug("Analytics sent to Discord successfully")
        :ok

      {:ok, {{_, status_code, _}, _headers, response_body}} ->
        Logger.warning(
          "Failed to send analytics to Discord. Status: #{status_code}, Body: #{response_body}"
        )

        :ok

      {:error, reason} ->
        Logger.warning("Failed to send analytics to Discord: #{inspect(reason)}")
        :ok
    end
  end
end
