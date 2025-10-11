defmodule SocialPomodoroWeb.SessionLiveTest do
  use SocialPomodoroWeb.ConnCase
  import Phoenix.LiveViewTest

  # Helper to create a connection with a user session
  defp setup_user_conn(user_id) do
    unique_id = "#{user_id}_#{System.unique_integer([:positive])}"

    build_conn()
    |> Plug.Test.init_test_session(%{"user_id" => unique_id})
  end

  # Helper to advance time by sending tick messages
  defp tick_room(room_pid, count) do
    for _ <- 1..count do
      send(room_pid, :tick)
      # Give the room a moment to process the tick
      Process.sleep(10)
    end
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
    test "redirects to lobby when break ends" do
      conn = setup_user_conn("userA")

      # Create a room through the normal flow
      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)

      # Extract room_name
      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
          [_, room_name] -> room_name
          _ -> nil
        end

      # Get room pid and modify its state for faster testing
      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)

      # Manually update the room to use shorter durations
      :sys.replace_state(room_pid, fn state ->
        %{state | duration_seconds: 1, break_duration_seconds: 2}
      end)

      # Join the room and start session
      {:ok, session_view, _html} = live(conn, "/room/#{room_name}")

      # Start the session
      session_view
      |> element("button[phx-click='start_session']")
      |> render_click()

      # Advance time for active session to complete (1 second duration + 1 tick to transition)
      tick_room(room_pid, 2)

      # Should now be in break
      html = render(session_view)
      assert html =~ "Great Work!"
      assert html =~ "Break time remaining"

      # Advance time for break to end (2 seconds + 1 tick to trigger redirect)
      tick_room(room_pid, 3)

      # Give LiveView time to process the redirect
      Process.sleep(50)

      # Should be redirected to lobby
      assert_redirect(session_view, "/")
    end

    test "does not redirect if user clicks 'Go Again Together'" do
      conn = setup_user_conn("userA")

      # Create a room through the normal flow
      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)

      # Extract room_name
      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
          [_, room_name] -> room_name
          _ -> nil
        end

      # Get room pid and modify its state for faster testing
      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)

      # Manually update the room to use shorter durations
      :sys.replace_state(room_pid, fn state ->
        %{state | duration_seconds: 1, break_duration_seconds: 3}
      end)

      # Join the room and start session
      {:ok, session_view, _html} = live(conn, "/room/#{room_name}")

      # Start the session
      session_view
      |> element("button[phx-click='start_session']")
      |> render_click()

      # Advance time for active session to complete (1 second duration + 1 tick to transition)
      tick_room(room_pid, 2)

      # Should now be in break
      html = render(session_view)
      assert html =~ "Great Work!"

      # Click "Go Again Together" - this marks user as ready and starts new session immediately (since only 1 user)
      session_view
      |> element("button[phx-click='go_again']")
      |> render_click()

      # Small delay to let the state update propagate
      Process.sleep(50)

      # Should be in active session again (not break)
      html = render(session_view)
      assert html =~ "Focus time remaining"
      refute html =~ "Great Work!"
    end
  end

  describe "auto-leave on navigation" do
    test "user is removed from room when navigating away from session" do
      conn = setup_user_conn("userA")
      user_id = get_session(conn, "user_id")

      # User A creates room
      {:ok, lobbyA, _html} = live(conn, "/")

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

      # Verify user is in the room
      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      room_state = SocialPomodoro.Room.get_state(room_pid)
      assert Enum.any?(room_state.participants, &(&1.user_id == user_id))

      # User A navigates to session page
      {:ok, session_view, _html} = live(conn, "/room/#{room_name}")

      # User is still in room
      room_state = SocialPomodoro.Room.get_state(room_pid)
      assert Enum.any?(room_state.participants, &(&1.user_id == user_id))

      # Stop the LiveView to simulate navigation away (this calls terminate/2)
      GenServer.stop(session_view.pid)

      # Give it a moment to process
      Process.sleep(50)

      # User should now be removed from the room
      room_state = SocialPomodoro.Room.get_state(room_pid)
      refute Enum.any?(room_state.participants, &(&1.user_id == user_id))
    end

    test "user is not removed when on redirect screen and navigates away" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      user_id_a = get_session(connA, "user_id")
      user_id_b = get_session(connB, "user_id")

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

      # User A should be in the room
      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      room_state = SocialPomodoro.Room.get_state(room_pid)
      assert Enum.any?(room_state.participants, &(&1.user_id == user_id_a))

      # User B tries to access room URL directly (shows redirect screen)
      {:ok, session_view_b, htmlB} = live(connB, "/room/#{room_name}")
      assert htmlB =~ "not in this room"

      # User B was never in the room
      room_state = SocialPomodoro.Room.get_state(room_pid)
      refute Enum.any?(room_state.participants, &(&1.user_id == user_id_b))

      # User B navigates away
      GenServer.stop(session_view_b.pid)
      Process.sleep(50)

      # User A should still be in room (B was never there, so nothing should change)
      room_state = SocialPomodoro.Room.get_state(room_pid)
      assert Enum.any?(room_state.participants, &(&1.user_id == user_id_a))
      refute Enum.any?(room_state.participants, &(&1.user_id == user_id_b))
    end
  end
end
