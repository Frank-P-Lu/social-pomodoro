defmodule SocialPomodoro.TelemetryHandler do
  @moduledoc """
  Handles telemetry events and sends analytics to Discord webhook and logs.

  All webhook sending is done asynchronously to prevent blocking the caller
  (typically a GenServer handling room state). This ensures that HTTP requests
  don't cause timeouts in critical code paths.
  """

  require Logger

  alias SocialPomodoro.Discord.Webhook

  @doc """
  Handles telemetry events and sends them to Discord webhook and logs for analytics.

  Note: This function returns immediately. Webhook requests are sent asynchronously
  in a separate process to avoid blocking.
  """
  def handle_event([:pomodoro, :room, :created], _measurements, metadata, _config) do
    user_id = metadata[:user_id]
    room_name = metadata[:room_name]
    duration_minutes = metadata[:duration_minutes]
    username = SocialPomodoro.UserRegistry.get_username(user_id)

    Logger.metadata(event_type: "room_created", user_id: user_id, username: username)

    Logger.info(
      "EVENT room_created room=#{room_name} user=#{username} duration=#{duration_minutes}"
    )

    send_analytics("Room Created", %{
      room_name: room_name,
      creator_user_id: user_id,
      duration_minutes: duration_minutes
    })
  end

  def handle_event([:pomodoro, :session, :started], _measurements, metadata, _config) do
    room_name = metadata[:room_name]
    participant_count = metadata[:participant_count]
    wait_time_seconds = metadata[:wait_time_seconds]

    Logger.metadata(event_type: "session_started")

    Logger.info(
      "EVENT session_started room=#{room_name} participants=#{participant_count} wait_time=#{wait_time_seconds}s"
    )

    send_analytics("Session Started", %{
      room_name: room_name,
      participant_user_ids: metadata[:participant_user_ids],
      participant_count: participant_count,
      wait_time_seconds: wait_time_seconds
    })
  end

  def handle_event([:pomodoro, :session, :restarted], _measurements, metadata, _config) do
    room_name = metadata[:room_name]
    participant_count = metadata[:participant_count]

    Logger.metadata(event_type: "session_restarted")
    Logger.info("EVENT session_restarted room=#{room_name} participants=#{participant_count}")

    send_analytics("Session Restarted", %{
      room_name: room_name,
      participant_user_ids: metadata[:participant_user_ids],
      participant_count: participant_count
    })
  end

  def handle_event([:pomodoro, :session, :completed], _measurements, metadata, _config) do
    room_name = metadata[:room_name]
    participant_count = metadata[:participant_count]
    duration_minutes = metadata[:duration_minutes]

    Logger.metadata(event_type: "session_completed")

    Logger.info(
      "EVENT session_completed room=#{room_name} participants=#{participant_count} duration=#{duration_minutes}"
    )

    send_analytics("Session Completed", %{
      room_name: room_name,
      participant_count: participant_count,
      duration_minutes: duration_minutes
    })
  end

  def handle_event([:pomodoro, :user, :rejoined], _measurements, metadata, _config) do
    user_id = metadata[:user_id]
    room_name = metadata[:room_name]
    room_status = metadata[:room_status]
    username = SocialPomodoro.UserRegistry.get_username(user_id)

    Logger.metadata(event_type: "user_rejoined", user_id: user_id, username: username)
    Logger.info("EVENT user_rejoined room=#{room_name} user=#{username} status=#{room_status}")

    send_analytics("User Rejoined", %{
      room_name: room_name,
      user_id: user_id,
      room_status: room_status
    })
  end

  def handle_event([:pomodoro, :user, :set_working_on], _measurements, metadata, _config) do
    user_id = metadata[:user_id]
    room_name = metadata[:room_name]
    text_length = metadata[:text_length]
    username = SocialPomodoro.UserRegistry.get_username(user_id)

    Logger.metadata(event_type: "working_on_set", user_id: user_id, username: username)
    Logger.info("EVENT working_on_set room=#{room_name} user=#{username} length=#{text_length}")

    send_analytics("Working On Set", %{
      room_name: room_name,
      user_id: user_id,
      text_length: text_length
    })
  end

  def handle_event([:pomodoro, :user, :connected], _measurements, metadata, _config) do
    user_id = metadata[:user_id]
    username = metadata[:username]
    user_agent = metadata[:user_agent]
    ip_address = metadata[:ip_address]

    Logger.metadata(
      event_type: "user_connected",
      user_id: user_id,
      username: username,
      user_agent: user_agent,
      ip_address: ip_address
    )

    Logger.info(
      "EVENT user_connected user=#{username} user_id=#{user_id} ip=#{ip_address} user_agent=#{user_agent}"
    )

    send_analytics("User Connected", %{
      user_id: user_id,
      username: username,
      user_agent: user_agent,
      ip_address: ip_address,
      referer: metadata[:referer],
      accept_language: metadata[:accept_language]
    })
  end

  defp send_analytics(event_type, data) do
    Webhook.send_analytics(event_type, data)
  end
end
