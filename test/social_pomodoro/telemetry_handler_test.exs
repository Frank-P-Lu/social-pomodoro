defmodule SocialPomodoro.TelemetryHandlerTest do
  use ExUnit.Case, async: true
  alias SocialPomodoro.TelemetryHandler

  import ExUnit.CaptureLog

  describe "handle_event/4 for room created" do
    test "logs room creation event when webhook not configured" do
      log =
        capture_log(fn ->
          TelemetryHandler.handle_event(
            [:pomodoro, :room, :created],
            %{count: 1},
            %{
              room_id: "test_room_123",
              user_id: "user_456",
              duration_minutes: 25
            },
            nil
          )
        end)

      assert log =~ "Discord webhook URL not configured"
      assert log =~ "Room Created"
    end
  end

  describe "handle_event/4 for session started" do
    test "logs session started event when webhook not configured" do
      log =
        capture_log(fn ->
          TelemetryHandler.handle_event(
            [:pomodoro, :session, :started],
            %{count: 1},
            %{
              room_id: "test_room_123",
              participant_user_ids: ["user_456", "user_789", "user_012"],
              participant_count: 3,
              wait_time_seconds: 45
            },
            nil
          )
        end)

      assert log =~ "Discord webhook URL not configured"
      assert log =~ "Session Started"
    end
  end

  describe "handle_event/4 for session restarted" do
    test "logs session restarted event when webhook not configured" do
      log =
        capture_log(fn ->
          TelemetryHandler.handle_event(
            [:pomodoro, :session, :restarted],
            %{count: 1},
            %{
              room_id: "test_room_123",
              participant_user_ids: ["user_456", "user_789"],
              participant_count: 2
            },
            nil
          )
        end)

      assert log =~ "Discord webhook URL not configured"
      assert log =~ "Session Restarted"
    end
  end

  describe "handle_event/4 for session completed" do
    test "logs session completed event when webhook not configured" do
      log =
        capture_log(fn ->
          TelemetryHandler.handle_event(
            [:pomodoro, :session, :completed],
            %{count: 1},
            %{
              room_id: "test_room_123",
              participant_count: 3,
              duration_minutes: 25
            },
            nil
          )
        end)

      assert log =~ "Discord webhook URL not configured"
      assert log =~ "Session Completed"
    end
  end

  describe "non-blocking behavior" do
    test "handle_event returns immediately even with webhook configured" do
      # Temporarily configure a webhook URL (won't actually send)
      original_config = Application.get_env(:social_pomodoro, :discord_webhook_url)

      try do
        # Set a fake webhook URL to trigger the async path
        Application.put_env(:social_pomodoro, :discord_webhook_url, "https://example.com/webhook")

        # Measure time taken - should be very fast (< 100ms) since it's async
        {time_microseconds, _result} =
          :timer.tc(fn ->
            TelemetryHandler.handle_event(
              [:pomodoro, :room, :created],
              %{count: 1},
              %{
                room_id: "test_room_123",
                user_id: "user_456",
                duration_minutes: 25
              },
              nil
            )
          end)

        time_milliseconds = time_microseconds / 1000

        # Assert that the call returns very quickly (< 100ms)
        # This proves it's non-blocking
        assert time_milliseconds < 100,
               "Expected handle_event to return in < 100ms, but took #{time_milliseconds}ms"
      after
        # Restore original config
        if original_config do
          Application.put_env(:social_pomodoro, :discord_webhook_url, original_config)
        else
          Application.delete_env(:social_pomodoro, :discord_webhook_url)
        end
      end
    end
  end
end
