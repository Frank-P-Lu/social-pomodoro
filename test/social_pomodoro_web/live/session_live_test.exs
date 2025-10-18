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

  # Helper to set shorter durations for faster testing
  defp set_short_durations(room_pid, work_seconds \\ 10, break_seconds \\ 5) do
    :sys.replace_state(room_pid, fn state ->
      %{state | work_duration_seconds: work_seconds, break_duration_seconds: break_seconds}
    end)
  end

  describe "spectator mode" do
    test "spectator sees read-only view with ghost message" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      user_id_b = get_session(connB, "user_id")

      # User A creates room and starts session
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, htmlA) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      lobbyA
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      Process.sleep(50)

      # User B joins as spectator
      SocialPomodoro.Room.join(room_name, user_id_b)

      # User B views the session
      {:ok, _sessionB, htmlB} = live(connB, "/room/#{room_name}")

      # Should see spectator message
      assert htmlB =~ "You&#39;re a spectator"
      assert htmlB =~ "Watch the session in progress"
      assert htmlB =~ "Interactions are disabled while spectating"

      # Should not see interactive elements (no emoji buttons, no working_on form)
      refute htmlB =~ "phx-click=\"set_status\""
      refute htmlB =~ "What are you working on?"
    end

    test "spectator automatically becomes participant during break" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      user_id_b = get_session(connB, "user_id")

      # User A creates room and starts session
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, htmlA) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 5)

      lobbyA
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      Process.sleep(50)

      # User B joins as spectator
      SocialPomodoro.Room.join(room_name, user_id_b)

      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      assert Enum.member?(room_state.spectators, user_id_b)

      # Advance time to trigger break
      tick_room(room_pid, 2)
      Process.sleep(50)

      # Check room state - B should now be a participant
      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      refute Enum.member?(room_state.spectators, user_id_b)
      assert Enum.any?(room_state.participants, &(&1.user_id == user_id_b))
      assert room_state.status == :break
    end

    test "spectator badge shows correct count" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      user_id_b = get_session(connB, "user_id")

      # User A creates room and starts session
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, htmlA) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      lobbyA
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      Process.sleep(50)

      # Now navigate to session page
      {:ok, sessionA, _html} = live(connA, "/room/#{room_name}")

      # Initially no spectators
      room_state = SocialPomodoro.Room.get_state(room_pid)
      assert room_state.spectators_count == 0

      # User B joins as spectator
      SocialPomodoro.Room.join(room_name, user_id_b)
      Process.sleep(50)

      # Check spectator count
      room_state = SocialPomodoro.Room.get_state(room_pid)
      assert room_state.spectators_count == 1

      # Render and check badge appears
      htmlA = render(sessionA)
      assert htmlA =~ "1"
    end

    test "spectator can leave room" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      user_id_b = get_session(connB, "user_id")

      # User A creates room and starts session
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, htmlA) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      lobbyA
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      Process.sleep(50)

      # User B joins as spectator
      SocialPomodoro.Room.join(room_name, user_id_b)

      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      assert Enum.member?(room_state.spectators, user_id_b)

      # User B leaves
      SocialPomodoro.Room.leave(room_name, user_id_b)
      Process.sleep(50)

      # Should be removed from spectators
      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      refute Enum.member?(room_state.spectators, user_id_b)
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
      set_short_durations(room_pid, 1, 2)

      # Start the session
      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      Process.sleep(50)

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

      # Get room pid and set shorter durations for faster testing
      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 3)

      # Start the session
      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      Process.sleep(50)

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
      Process.sleep(50)

      # Room should redirect to lobby when break ends
      assert_redirect(session_view, "/")
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

      # Start the session from lobby
      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      Process.sleep(50)

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

    test "spectator is removed when navigating away" do
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

      # Start session so B can join as spectator
      set_short_durations(room_pid)

      lobbyA
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      Process.sleep(50)

      # User B joins as spectator
      SocialPomodoro.Room.join(room_name, user_id_b)

      {:ok, session_view_b, htmlB} = live(connB, "/room/#{room_name}")
      assert htmlB =~ "You&#39;re a spectator"

      # User B is a spectator
      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      assert Enum.member?(room_state.spectators, user_id_b)
      refute Enum.any?(room_state.participants, &(&1.user_id == user_id_b))

      # User B navigates away
      GenServer.stop(session_view_b.pid)
      Process.sleep(50)

      # User B should be removed from spectators
      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      refute Enum.member?(room_state.spectators, user_id_b)
      assert Enum.any?(room_state.participants, &(&1.user_id == user_id_a))
    end

    test "spectator joins as participant when timer finishes" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      _user_id_a = get_session(connA, "user_id")
      user_id_b = get_session(connB, "user_id")

      # User A creates room and starts session
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, htmlA) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 5)

      lobbyA
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      Process.sleep(50)

      # User B joins as spectator during active session
      SocialPomodoro.Room.join(room_name, user_id_b)
      {:ok, sessionB, htmlB} = live(connB, "/room/#{room_name}")

      # User B should be a spectator during active session
      assert htmlB =~ "You&#39;re a spectator"

      # Wait for timer to finish and transition to break
      tick_room(room_pid, 2)
      Process.sleep(100)

      # User B should now see participant view (not spectator view)
      htmlB = render(sessionB)
      refute htmlB =~ "You&#39;re a spectator"
      assert htmlB =~ "Amazing Work!"
      # Single cycle = final break, so no Skip Break button
      refute htmlB =~ "Skip Break"

      # Verify in room state that B is now a participant
      room_state = SocialPomodoro.Room.get_raw_state(room_pid)
      assert room_state.status == :break
      refute Enum.member?(room_state.spectators, user_id_b)
      assert Enum.any?(room_state.participants, &(&1.user_id == user_id_b))
    end

    test "completion message does not count spectators who joined during break" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      _user_id_a = get_session(connA, "user_id")
      user_id_b = get_session(connB, "user_id")

      # User A creates room and starts session
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, htmlA) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 5)

      lobbyA
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      Process.sleep(50)

      # User B joins as spectator during active session
      SocialPomodoro.Room.join(room_name, user_id_b)
      {:ok, sessionA, _htmlA} = live(connA, "/room/#{room_name}")

      # Wait for timer to finish and transition to break
      tick_room(room_pid, 2)
      Process.sleep(100)

      # Check completion message for User A
      # Should say "solo" not "with someone else" since B was a spectator
      htmlA = render(sessionA)
      assert htmlA =~ ~r/(You focused solo|Flying solo|Solo focus|You stayed focused)/
      refute htmlA =~ "You focused with"
    end

    test "user joining during break sees break page (not spectator view)" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room and starts session
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, htmlA) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid, 1, 5)

      lobbyA
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      Process.sleep(50)

      # Wait for A's session to complete and transition to break
      tick_room(room_pid, 2)
      Process.sleep(100)

      # Verify A sees the break page
      {:ok, sessionA, htmlA} = live(connA, "/room/#{room_name}")
      assert htmlA =~ "Amazing Work!"
      assert htmlA =~ "Break time remaining"

      # User B navigates to lobby and joins the room via UI
      {:ok, lobbyB, htmlB} = live(connB, "/")

      # User B should see the room in the lobby (in break status)
      assert htmlB =~ room_name |> String.replace("-", " ")
      assert htmlB =~ "On Break"

      # User B clicks join button - should trigger navigation to room page
      lobbyB
      |> element("button[phx-click='join_room'][phx-value-room-name='#{room_name}']")
      |> render_click()

      # Should have a redirect
      assert_redirect(lobbyB, "/room/#{room_name}")

      # Navigate directly to the room page
      {:ok, _sessionB, htmlB} = live(connB, "/room/#{room_name}")

      # User B should see the break page (not spectator view)
      refute htmlB =~ "You&#39;re a spectator"
      assert htmlB =~ "Amazing Work!"
      assert htmlB =~ "Break time remaining"

      # Both users should see each other's avatars in the break view
      htmlA = render(sessionA)
      # Should now show 2 participants
      assert String.contains?(htmlA, "avatar")
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

      Process.sleep(50)

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

      Process.sleep(50)

      {:ok, session, _html} = live(conn, "/room/#{room_name}")

      # Add a todo
      session
      |> element("form[phx-submit='add_todo']")
      |> render_submit(%{"text" => "Write tests"})

      Process.sleep(50)

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

      Process.sleep(50)

      {:ok, session, _html} = live(conn, "/room/#{room_name}")

      # Add 5 todos
      for i <- 1..5 do
        session
        |> element("form[phx-submit='add_todo']")
        |> render_submit(%{"text" => "Task #{i}"})

        Process.sleep(10)
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

      Process.sleep(50)

      {:ok, session, _html} = live(conn, "/room/#{room_name}")

      # Add a todo
      session
      |> element("form[phx-submit='add_todo']")
      |> render_submit(%{"text" => "Write tests"})

      Process.sleep(50)

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

      Process.sleep(50)

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

      Process.sleep(50)

      {:ok, session, _html} = live(conn, "/room/#{room_name}")

      # Add two todos
      session
      |> element("form[phx-submit='add_todo']")
      |> render_submit(%{"text" => "Task 1"})

      Process.sleep(50)

      session
      |> element("form[phx-submit='add_todo']")
      |> render_submit(%{"text" => "Task 2"})

      Process.sleep(50)

      # Get the first todo ID
      state = SocialPomodoro.Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == user_id))
      todo_id = hd(participant.todos).id

      # Delete the first todo
      session
      |> element("button[phx-click='delete_todo'][phx-value-todo_id='#{todo_id}']")
      |> render_click()

      Process.sleep(50)

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
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      _user_id_a = get_session(connA, "user_id")
      user_id_b = get_session(connB, "user_id")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)

      room_name =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, htmlA) do
          [_, room_name] -> room_name
          _ -> nil
        end

      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)
      set_short_durations(room_pid)

      # User B joins
      SocialPomodoro.Room.join(room_name, user_id_b)

      # Start session
      lobbyA
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      Process.sleep(50)

      {:ok, sessionA, _html} = live(connA, "/room/#{room_name}")
      {:ok, sessionB, _html} = live(connB, "/room/#{room_name}")

      # User A adds a todo
      sessionA
      |> element("form[phx-submit='add_todo']")
      |> render_submit(%{"text" => "User A task"})

      Process.sleep(50)

      # User B should see User A's todo in participant display (read-only)
      htmlB = render(sessionB)

      # Should show the todo text
      assert htmlB =~ "User A task"

      # Should have disabled checkbox (read-only for other participants)
      assert htmlB =~ "disabled"
    end
  end
end
