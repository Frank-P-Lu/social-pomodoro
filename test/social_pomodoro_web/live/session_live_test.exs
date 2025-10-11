defmodule SocialPomodoroWeb.SessionLiveTest do
  use SocialPomodoroWeb.ConnCase
  import Phoenix.LiveViewTest

  # Helper to create a connection with a user session
  defp setup_user_conn(user_id) do
    unique_id = "#{user_id}_#{System.unique_integer([:positive])}"

    build_conn()
    |> Plug.Test.init_test_session(%{"user_id" => unique_id})
  end

  describe "non-participant redirect" do
    test "non-participant sees redirect screen with countdown" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)

      # Extract room_name
      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, htmlA) do
          [_, room_name] -> room_name
          _ -> nil
        end

      # User B tries to access room URL directly without joining
      {:ok, _sessionB, htmlB} = live(connB, "/room/#{room_name}")

      # Should see redirect screen (apostrophes are HTML-encoded)
      assert htmlB =~ "Oops"
      assert htmlB =~ "not in this room"
      assert htmlB =~ "Heading back to the lobby"
      assert htmlB =~ "Go to Lobby Now"

      # Should show countdown starting at 5
      assert htmlB =~ "5"
    end

    test "participant does not see redirect screen" do
      connA = setup_user_conn("userA")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)

      # Extract room_name
      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, htmlA) do
          [_, room_name] -> room_name
          _ -> nil
        end

      # User A accesses their own room
      {:ok, _sessionA, htmlA_session} = live(connA, "/room/#{room_name}")

      # Should NOT see redirect screen
      refute htmlA_session =~ "Oops! You're not in this room"
      # Should see waiting room instead
      assert htmlA_session =~ "Waiting to Start"
    end
  end

  describe "break timer auto-redirect" do
    test "shows flash message at 10 seconds and redirects to lobby when break ends" do
      conn = setup_user_conn("userA")

      # Create a room with very short durations for testing
      {:ok, room_pid} =
        SocialPomodoro.RoomRegistry.create_room(
          name: "test-room-#{System.unique_integer([:positive])}",
          creator: conn.assigns.plug_session["user_id"],
          duration_seconds: 1,
          break_duration_seconds: 11,
          tick_interval: 100
        )

      room_state = SocialPomodoro.Room.get_state(room_pid)
      room_name = room_state.name

      # Join the room and start session
      {:ok, session_view, _html} = live(conn, "/room/#{room_name}")

      # Start the session
      session_view
      |> element("button[phx-click='start_session']")
      |> render_click()

      # Wait for active session to complete (1 second + buffer)
      Process.sleep(1200)

      # Should now be in break
      html = render(session_view)
      assert html =~ "Great Work!"
      assert html =~ "Break time remaining"

      # Wait until 10 seconds remaining (11 - 10 = 1 second + buffer)
      Process.sleep(1200)

      # Should see flash message
      assert render(session_view) =~ "Break ending soon"
      assert render(session_view) =~ "Returning to lobby in 10 seconds"

      # Wait for break to almost end (9 more seconds + buffer)
      Process.sleep(9200)

      # Should be redirected to lobby (redirects at 1 second remaining)
      assert_redirect(session_view, "/")
    end

    test "does not redirect if user clicks 'Go Again Together'" do
      conn = setup_user_conn("userA")

      # Create a room with very short durations for testing
      {:ok, room_pid} =
        SocialPomodoro.RoomRegistry.create_room(
          name: "test-room-#{System.unique_integer([:positive])}",
          creator: conn.assigns.plug_session["user_id"],
          duration_seconds: 1,
          break_duration_seconds: 3,
          tick_interval: 100
        )

      room_state = SocialPomodoro.Room.get_state(room_pid)
      room_name = room_state.name

      # Join the room and start session
      {:ok, session_view, _html} = live(conn, "/room/#{room_name}")

      # Start the session
      session_view
      |> element("button[phx-click='start_session']")
      |> render_click()

      # Wait for active session to complete
      Process.sleep(1200)

      # Should now be in break
      html = render(session_view)
      assert html =~ "Great Work!"

      # Click "Go Again Together"
      session_view
      |> element("button[phx-click='go_again']")
      |> render_click()

      # Wait for break to end
      Process.sleep(3200)

      # Should NOT be redirected, should be in active session again
      html = render(session_view)
      assert html =~ "Focus time remaining"
      refute html =~ "Great Work!"
    end
  end
end
