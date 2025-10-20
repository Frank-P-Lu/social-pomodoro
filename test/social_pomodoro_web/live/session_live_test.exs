defmodule SocialPomodoroWeb.SessionLiveTest do
  use SocialPomodoroWeb.ConnCase
  import Phoenix.LiveViewTest
  import SocialPomodoro.TestHelpers

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
      sleep_short()
    end
  end

  # Helper to set shorter durations for faster testing
  defp set_short_durations(room_pid, work_seconds \\ 10, break_seconds \\ 5, opts \\ []) do
    :sys.replace_state(room_pid, fn state ->
      total_cycles = Keyword.get(opts, :total_cycles, state.total_cycles)

      %{
        state
        | work_duration_seconds: work_seconds,
          break_duration_seconds: break_seconds,
          total_cycles: total_cycles
      }
    end)
  end

  describe "spectator mode" do
    test "spectator sees read-only view with ghost message" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      user_id_b = get_session(conn_b, "user_id")

      # User A creates room and starts session
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html_a) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      lobby_a
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # User B joins as spectator
      SocialPomodoro.Room.join(room_name, user_id_b)

      # User B views the session
      {:ok, _session_b, html_b} = live(conn_b, "/room/#{room_name}")

      # Should see spectator message
      assert html_b =~ "You&#39;re a spectator"
      assert html_b =~ "Watch the session in progress"
      assert html_b =~ "Interactions are disabled while spectating"

      # Should not see interactive elements (no emoji buttons, no working_on form)
      refute html_b =~ "phx-click=\"set_status\""
      refute html_b =~ "What are you working on?"
    end

    test "spectator automatically becomes participant during break" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      user_id_b = get_session(conn_b, "user_id")

      # User A creates room and starts session
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html_a) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 5)

      lobby_a
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # User B joins as spectator
      SocialPomodoro.Room.join(room_name, user_id_b)

      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      assert Enum.member?(room_state.spectators, user_id_b)

      # Advance time to trigger break
      tick_room(room_pid, 2)
      sleep_short()

      # Check room state - B should now be a participant
      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      refute Enum.member?(room_state.spectators, user_id_b)
      assert Enum.any?(room_state.participants, &(&1.user_id == user_id_b))
      assert room_state.status == :break
    end

    test "spectator badge shows correct count" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      user_id_b = get_session(conn_b, "user_id")

      # User A creates room and starts session
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html_a) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      lobby_a
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # Now navigate to session page
      {:ok, session_a, _html} = live(conn_a, "/room/#{room_name}")

      # Initially no spectators
      room_state = SocialPomodoro.Room.get_state(room_pid)
      assert room_state.spectators_count == 0

      # User B joins as spectator
      SocialPomodoro.Room.join(room_name, user_id_b)
      sleep_short()

      # Check spectator count
      room_state = SocialPomodoro.Room.get_state(room_pid)
      assert room_state.spectators_count == 1

      # Render and check badge appears
      html_a = render(session_a)
      assert html_a =~ "1"
    end

    test "spectator can leave room" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      user_id_b = get_session(conn_b, "user_id")

      # User A creates room and starts session
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html_a) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      lobby_a
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # User B joins as spectator
      SocialPomodoro.Room.join(room_name, user_id_b)

      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      assert Enum.member?(room_state.spectators, user_id_b)

      # User B leaves
      SocialPomodoro.Room.leave(room_name, user_id_b)
      sleep_short()

      # Should be removed from spectators
      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      refute Enum.member?(room_state.spectators, user_id_b)
    end

    test "joining mid-session via direct link renders without errors" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room and starts session
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html_a) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 5)

      lobby_a
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # User B joins via direct link (not via lobby) - simulates sharing link
      {:ok, session_b, html_b} = live(conn_b, "/room/#{room_name}")

      # Should successfully render spectator view without errors
      assert html_b =~ "You&#39;re a spectator"
      assert html_b =~ "Watch the session in progress"

      # Advance to break and verify it still works
      tick_room(room_pid, 2)
      sleep_short()

      html_b = render(session_b)

      # Should now see break view as participant
      assert html_b =~ "Great Work!"
      assert html_b =~ "Break time remaining"
      # Should show task count even when joining mid-session
      assert html_b =~ "0/0 tasks"
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

      # Get room pid and set shorter durations for faster testing
      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 2, total_cycles: 1)

      # Start the session
      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # Join the room
      {:ok, session_view, _html} = live(conn, "/room/#{room_name}")

      # Advance time for active session to complete (1 second duration + 1 tick to transition)
      tick_room(room_pid, 2)

      # Should now be in break (single cycle = final break = "Amazing Work!")
      html = render(session_view)
      assert html =~ "Amazing Work!"
      assert html =~ "Break time remaining"

      # Advance time for break to end (2 seconds + 1 tick to trigger redirect)
      tick_room(room_pid, 3)

      # Give LiveView time to process the redirect
      sleep_short()

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

      # Get room pid and set shorter durations for faster testing
      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 3, total_cycles: 1)

      # Start the session
      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # Join the room
      {:ok, session_view, _html} = live(conn, "/room/#{room_name}")

      # Advance time for active session to complete (1 second duration + 1 tick to transition)
      tick_room(room_pid, 2)

      # Should now be in break (single cycle = final break)
      html = render(session_view)
      assert html =~ "Amazing Work!"

      # Skip break button should NOT appear on final break
      refute html =~ "Skip Break"

      # Wait for the break to complete and room to close
      tick_room(room_pid, 4)
      sleep_short()

      # Room should redirect to lobby when break ends
      assert_redirect(session_view, "/")
    end
  end

  describe "auto-leave on navigation" do
    test "user is removed from room when navigating away from session" do
      conn = setup_user_conn("userA")
      user_id = get_session(conn, "user_id")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)

      # Extract room_name
      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html_a) do
          [_, room_name] -> room_name
          _ -> nil
        end

      # Verify user is in the room
      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      room_state = SocialPomodoro.Room.get_state(room_pid)
      assert Enum.any?(room_state.participants, &(&1.user_id == user_id))

      # Start the session from lobby
      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # User A navigates to session page
      {:ok, session_view, _html} = live(conn, "/room/#{room_name}")

      # User is still in room
      room_state = SocialPomodoro.Room.get_state(room_pid)
      assert Enum.any?(room_state.participants, &(&1.user_id == user_id))

      # Stop the LiveView to simulate navigation away (this calls terminate/2)
      GenServer.stop(session_view.pid)

      # Give it a moment to process
      sleep_short()

      # User should now be removed from the room
      room_state = SocialPomodoro.Room.get_state(room_pid)
      refute Enum.any?(room_state.participants, &(&1.user_id == user_id))
    end

    test "spectator is removed when navigating away" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      user_id_a = get_session(conn_a, "user_id")
      user_id_b = get_session(conn_b, "user_id")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)

      # Extract room_name
      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html_a) do
          [_, room_name] -> room_name
          _ -> nil
        end

      # User A should be in the room
      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      room_state = SocialPomodoro.Room.get_state(room_pid)
      assert Enum.any?(room_state.participants, &(&1.user_id == user_id_a))

      # Start session so B can join as spectator
      set_short_durations(room_pid)

      lobby_a
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # User B joins as spectator
      SocialPomodoro.Room.join(room_name, user_id_b)

      {:ok, session_view_b, html_b} = live(conn_b, "/room/#{room_name}")
      assert html_b =~ "You&#39;re a spectator"

      # User B is a spectator
      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      assert Enum.member?(room_state.spectators, user_id_b)
      refute Enum.any?(room_state.participants, &(&1.user_id == user_id_b))

      # User B navigates away
      GenServer.stop(session_view_b.pid)
      sleep_short()

      # User B should be removed from spectators
      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      refute Enum.member?(room_state.spectators, user_id_b)
      assert Enum.any?(room_state.participants, &(&1.user_id == user_id_a))
    end

    test "spectator joins as participant when timer finishes" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      _user_id_a = get_session(conn_a, "user_id")
      user_id_b = get_session(conn_b, "user_id")

      # User A creates room and starts session
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html_a) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 5, total_cycles: 1)

      lobby_a
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # User B joins as spectator during active session
      SocialPomodoro.Room.join(room_name, user_id_b)
      {:ok, session_b, html_b} = live(conn_b, "/room/#{room_name}")

      # User B should be a spectator during active session
      assert html_b =~ "You&#39;re a spectator"

      # Wait for timer to finish and transition to break
      tick_room(room_pid, 2)
      sleep_short()

      # User B should now see participant view (not spectator view)
      html_b = render(session_b)
      refute html_b =~ "You&#39;re a spectator"
      assert html_b =~ "Amazing Work!"
      # Single cycle = final break, so no Skip Break button
      refute html_b =~ "Skip Break"

      # Verify in room state that B is now a participant
      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      assert room_state.status == :break
      refute Enum.member?(room_state.spectators, user_id_b)
      assert Enum.any?(room_state.participants, &(&1.user_id == user_id_b))
    end

    test "completion message does not count spectators who joined during break" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      _user_id_a = get_session(conn_a, "user_id")
      user_id_b = get_session(conn_b, "user_id")

      # User A creates room and starts session
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html_a) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 5)

      lobby_a
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # User B joins as spectator during active session
      SocialPomodoro.Room.join(room_name, user_id_b)
      {:ok, session_a, _html_a} = live(conn_a, "/room/#{room_name}")

      # Wait for timer to finish and transition to break
      tick_room(room_pid, 2)
      sleep_short()

      # Check completion message for User A
      # Should say "solo" not "with someone else" since B was a spectator
      html_a = render(session_a)
      assert html_a =~ ~r/(You focused solo|Flying solo|Solo focus|You stayed focused)/
      refute html_a =~ "You focused with"
    end

    test "user joining during break sees break page (not spectator view)" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room and starts session
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html_a) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 5, total_cycles: 1)

      lobby_a
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # Wait for A's session to complete and transition to break
      tick_room(room_pid, 2)
      sleep_short()

      # Verify A sees the break page
      {:ok, session_a, html_a} = live(conn_a, "/room/#{room_name}")
      assert html_a =~ "Amazing Work!"
      assert html_a =~ "Break time remaining"

      # User B navigates to lobby and joins the room via UI
      {:ok, lobby_b, html_b} = live(conn_b, "/")

      # User B should see the room in the lobby (in break status)
      assert html_b =~ room_name |> String.replace("-", " ")
      assert html_b =~ "On Break"

      # User B clicks join button - should trigger navigation to room page
      lobby_b
      |> element("button[phx-click='join_room'][phx-value-room-name='#{room_name}']")
      |> render_click()

      # Should have a redirect
      assert_redirect(lobby_b, "/room/#{room_name}")

      # Navigate directly to the room page
      {:ok, _session_b, html_b} = live(conn_b, "/room/#{room_name}")

      # User B should see the break page (not spectator view)
      refute html_b =~ "You&#39;re a spectator"
      assert html_b =~ "Amazing Work!"
      assert html_b =~ "Break time remaining"

      # Both users should see each other's avatars in the break view
      html_a = render(session_a)
      # Should now show 2 participants
      assert String.contains?(html_a, "avatar")
    end
  end

  describe "todo list UI" do
    test "shows todo input form during active session" do
      conn = setup_user_conn("userA")

      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      {:ok, _session, html} = live(conn, "/room/#{room_name}")

      # Should show todo input
      assert html =~ "What are you working on?"
      assert html =~ "phx-submit=\"add_todo\""
    end

    test "user can add todo via form" do
      conn = setup_user_conn("userA")
      user_id = get_session(conn, "user_id")

      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      {:ok, session, _html} = live(conn, "/room/#{room_name}")

      # Add a todo
      session
      |> element("form[phx-submit='add_todo']")
      |> render_submit(%{"text" => "Write tests"})

      sleep_short()

      # Verify todo appears in UI
      html = render(session)
      assert html =~ "Write tests"

      # Verify todo has checkbox and delete button
      assert html =~ "phx-click=\"toggle_todo\""
      assert html =~ "phx-click=\"delete_todo\""

      # Verify in room state
      state = SocialPomodoro.Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == user_id))
      assert length(participant.todos) == 1
      assert hd(participant.todos).text == "Write tests"
    end

    test "input disabled when 5 todos exist" do
      conn = setup_user_conn("userA")

      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      {:ok, session, _html} = live(conn, "/room/#{room_name}")

      # Add 5 todos
      for i <- 1..5 do
        session
        |> element("form[phx-submit='add_todo']")
        |> render_submit(%{"text" => "Task #{i}"})

        sleep_short()
      end

      html = render(session)

      # Should show max todos message
      assert html =~ "Max 5 todos reached"

      # Input should be disabled
      assert html =~ "disabled"
    end

    test "user can toggle todo checkbox" do
      conn = setup_user_conn("userA")
      user_id = get_session(conn, "user_id")

      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      {:ok, session, _html} = live(conn, "/room/#{room_name}")

      # Add a todo
      session
      |> element("form[phx-submit='add_todo']")
      |> render_submit(%{"text" => "Write tests"})

      sleep_short()

      # Get the todo ID from room state
      state = SocialPomodoro.Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == user_id))
      todo_id = hd(participant.todos).id

      # Toggle the todo
      session
      |> element(
        "input[type='checkbox'][phx-click='toggle_todo'][phx-value-todo_id='#{todo_id}']"
      )
      |> render_click()

      sleep_short()

      # Verify todo is marked complete
      state = SocialPomodoro.Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == user_id))
      assert hd(participant.todos).completed == true

      # UI should show strikethrough
      html = render(session)
      assert html =~ "line-through"
    end

    test "user can delete todo via trash icon" do
      conn = setup_user_conn("userA")
      user_id = get_session(conn, "user_id")

      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      {:ok, session, _html} = live(conn, "/room/#{room_name}")

      # Add two todos
      session
      |> element("form[phx-submit='add_todo']")
      |> render_submit(%{"text" => "Task 1"})

      sleep_short()

      session
      |> element("form[phx-submit='add_todo']")
      |> render_submit(%{"text" => "Task 2"})

      sleep_short()

      # Get the first todo ID
      state = SocialPomodoro.Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == user_id))
      todo_id = hd(participant.todos).id

      # Delete the first todo
      session
      |> element("button[phx-click='delete_todo'][phx-value-todo_id='#{todo_id}']")
      |> render_click()

      sleep_short()

      # Verify only one todo remains
      state = SocialPomodoro.Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == user_id))
      assert length(participant.todos) == 1
      assert hd(participant.todos).text == "Task 2"

      # UI should only show Task 2
      html = render(session)
      assert html =~ "Task 2"
      refute html =~ "Task 1"
    end

    test "other participants see todos in read-only mode" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      _user_id_a = get_session(conn_a, "user_id")
      user_id_b = get_session(conn_b, "user_id")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html_a) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      # User B joins
      SocialPomodoro.Room.join(room_name, user_id_b)

      # Start session
      lobby_a
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      {:ok, session_a, _html} = live(conn_a, "/room/#{room_name}")
      {:ok, session_b, _html} = live(conn_b, "/room/#{room_name}")

      # User A adds a todo
      session_a
      |> element("form[phx-submit='add_todo']")
      |> render_submit(%{"text" => "User A task"})

      sleep_short()

      # User B should see User A's todo in participant display (read-only)
      html_b = render(session_b)

      # Should show the todo text
      assert html_b =~ "User A task"

      # Should have disabled checkbox (read-only for other participants)
      assert html_b =~ "disabled"
    end
  end

  describe "multi-cycle room navigation" do
    test "users remain on session page when break ends with remaining cycles" do
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

      # Get room pid and set 3 cycles with short durations
      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 2, 2, total_cycles: 3)

      # Start the session
      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # Join the room
      {:ok, session_view, _html} = live(conn, "/room/#{room_name}")

      # Verify we're in cycle 1, active session
      state = SocialPomodoro.Room.get_state(room_pid)
      assert state.status == :active
      assert state.current_cycle == 1

      # Advance time for active session to complete (2 -> 1 -> 0 -> break)
      tick_room(room_pid, 3)

      # Should now be in break
      html = render(session_view)
      assert html =~ "Great Work!"
      assert html =~ "Break time remaining"

      state = SocialPomodoro.Room.get_state(room_pid)
      assert state.status == :break
      assert state.current_cycle == 1

      # Advance time for break to end (2 -> 1 -> 0 -> next cycle)
      tick_room(room_pid, 3)

      # Give LiveView time to process the state change
      sleep_short()

      # CRITICAL: User should NOT be redirected to lobby since we have 2 more cycles
      # They should remain on the session page and see cycle 2
      state = SocialPomodoro.Room.get_state(room_pid)
      assert state.status == :active
      assert state.current_cycle == 2

      # Verify we're still on the session page (NOT redirected)
      html = render(session_view)
      assert html =~ "Focus time remaining"
      assert html =~ "2 of 3"
      refute html =~ "Amazing Work!"
    end

    test "users are redirected to lobby when final break ends" do
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

      # Get room pid and set 1 cycle (final break should redirect)
      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 2, total_cycles: 1)

      # Start the session
      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      # Join the room
      {:ok, session_view, _html} = live(conn, "/room/#{room_name}")

      # Advance time for active session to complete
      tick_room(room_pid, 2)

      # Should be in final break
      html = render(session_view)
      assert html =~ "Amazing Work!"

      # Advance time for break to end
      tick_room(room_pid, 3)

      # Give LiveView time to process the redirect
      sleep_short()

      # Should be redirected to lobby since this was the final cycle
      assert_redirect(session_view, "/")
    end
  end

  describe "tab functionality" do
    test "todo tab is selected by default during active session" do
      conn = setup_user_conn("userA")

      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      {:ok, session, _html} = live(conn, "/room/#{room_name}")

      html = render(session)

      # Todo tab should be checked (using radio input now)
      assert html =~ ~r/input[^>]*aria-label="Todo"[^>]*checked/
      # Todo content should be visible
      assert html =~ "What are you working on?"
    end

    test "chat tab is disabled during active session" do
      conn = setup_user_conn("userA")

      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      {:ok, session, _html} = live(conn, "/room/#{room_name}")

      html = render(session)

      # Chat tab should be disabled (using radio input now)
      assert html =~ ~r/input[^>]*aria-label="Chat"[^>]*disabled/
    end

    test "chat tab is enabled during break" do
      conn = setup_user_conn("userA")

      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 5)

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      {:ok, session, _html} = live(conn, "/room/#{room_name}")

      # Tick to break
      tick_room(room_pid, 2)

      html = render(session)

      # Chat tab should NOT be disabled (using radio input now)
      refute html =~ ~r/input[^>]*aria-label="Chat"[^>]*disabled/
    end

    test "switching tabs shows correct content" do
      conn = setup_user_conn("userA")

      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 5)

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      {:ok, session, _html} = live(conn, "/room/#{room_name}")

      # Tick to break
      tick_room(room_pid, 2)

      # Switch to chat tab (using radio input now)
      session
      |> element("input[phx-value-tab='chat']")
      |> render_click()

      html = render(session)

      # Chat tab should be checked
      assert html =~ ~r/input[^>]*aria-label="Chat"[^>]*checked/
      # Both inputs exist in DOM (daisyUI tabs behavior), but chat should be active
      assert html =~ "Say something..."
      assert html =~ "What are you working on?"

      # Switch back to todo tab (using radio input now)
      session
      |> element("input[phx-value-tab='todo']")
      |> render_click()

      html = render(session)

      # Todo tab should be checked
      assert html =~ ~r/input[^>]*aria-label="Todo"[^>]*checked/
      # Both inputs exist in DOM (daisyUI tabs behavior), but todo should be active
      assert html =~ "What are you working on?"
      assert html =~ "Say something..."
    end

    test "tab resets to todo when break ends" do
      conn = setup_user_conn("userA")

      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 5)

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      sleep_short()

      {:ok, session, _html} = live(conn, "/room/#{room_name}")

      # Tick to break
      tick_room(room_pid, 2)

      # Verify we're in break and chat tab is available
      html = render(session)
      assert html =~ "Break time remaining"

      # Switch to chat tab during break (using radio input now)
      session
      |> element("input[phx-value-tab='chat']")
      |> render_click()

      html = render(session)
      assert html =~ "Say something..."
      # Chat tab should be checked
      assert html =~ ~r/input[^>]*aria-label="Chat"[^>]*checked/
    end
  end
end
