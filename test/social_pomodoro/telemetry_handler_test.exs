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
end
