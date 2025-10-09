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

  def handle_event([:pomodoro, :user, :rejoined], _measurements, metadata, _config) do
    send_analytics("User Rejoined", %{
      room_name: metadata[:room_name],
      user_id: metadata[:user_id],
      room_status: metadata[:room_status]
    })
  end

  def handle_event([:pomodoro, :user, :set_working_on], _measurements, metadata, _config) do
    send_analytics("Working On Set", %{
      room_name: metadata[:room_name],
      user_id: metadata[:user_id],
      text_length: metadata[:text_length]
    })
  end

  defp send_analytics(event_type, data) do
    SocialPomodoro.Discord.Webhook.send_analytics(event_type, data)
  end
end
