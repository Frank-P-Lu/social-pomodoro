defmodule SocialPomodoro.TelemetryHandlerTest do
  use ExUnit.Case, async: true
  alias SocialPomodoro.TelemetryHandler

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
                room_name: "test_room_123",
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
