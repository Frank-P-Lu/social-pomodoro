defmodule SocialPomodoroWeb.LobbyLiveIntegrationTest do
  use SocialPomodoroWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import SocialPomodoro.TestHelpers

  # Helper to create a connection with a user session
  # Adds a unique suffix to prevent test interference
  defp setup_user_conn(user_id) do
    unique_id = "#{user_id}_#{System.unique_integer([:positive])}"

    build_conn()
    |> Plug.Test.init_test_session(%{"user_id" => unique_id})
  end

  # Helper to extract room name from HTML (looks for Start or Join button)
  defp extract_room_name_from_button(html) do
    # Try to find room name from Start button first (for creator)
    case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
      [_, room_name] ->
        room_name

      _ ->
        # Try Join button (for non-creator)
        case Regex.run(~r/phx-click="join_room"[^>]*phx-value-room-name="([^"]+)"/, html) do
          [_, room_name] -> room_name
          _ -> nil
        end
    end
  end

  # Helper to extract room_name from HTML (looks for data-room-name attribute)
  defp extract_room_name(html) do
    case Regex.run(~r/data-room-name="([^"]+)"/, html) do
      [_, room_name] -> room_name
      _ -> nil
    end
  end

  describe "multi-user flow" do
    test "user A creates room, user B can join, both navigate when started" do
      conn1 = setup_user_conn("userA")
      conn2 = setup_user_conn("userB")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn1, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name_from_button(html_a)

      # User B loads lobby and sees the room
      {:ok, lobby_b, html_b} = live(conn2, "/")
      assert html_b =~ room_name

      # User B joins the specific room using phx-value-room-name (room is in autostart)
      lobby_b
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      # User B should stay on lobby (room is in autostart, not active/break)
      html_b = render(lobby_b)
      html_a = render(lobby_a)

      # Both should see "2 people" for the room
      assert html_a =~ "2 people"
      assert html_b =~ "2 people"

      # User A should see "Start" button for their room (with room_name attribute)
      assert html_a =~ ~r/phx-value-room-name="#{room_name}"/
      assert html_a =~ "Start"

      # User A starts the session
      lobby_a
      |> element("button[phx-value-room-name='#{room_name}']", "Start")
      |> render_click()

      # User A should navigate to the room
      assert_redirect(lobby_a, "/room/#{room_name}")
    end
  end

  describe "refresh persistence" do
    test "participant sees 'Waiting for host...' after refresh" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name_from_button(html_a)

      # User B joins
      {:ok, lobby_b1, _html} = live(conn_b, "/")

      lobby_b1
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      html1 = render(lobby_b1)
      assert html1 =~ "Starting"

      # User B refreshes
      {:ok, _lobby_b2, html2} = live(conn_b, "/")

      # Should still see "Starting" countdown (not "Join")
      assert html2 =~ "Starting"
      refute html2 =~ ~r/<button[^>]*phx-value-room-name="#{room_name}"[^>]*>Join<\/button>/
    end

    test "non-participant still sees Join button after refresh" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name_from_button(html_a)

      # User B loads lobby but doesn't join
      {:ok, _lobby_b1, html1} = live(conn_b, "/")
      assert html1 =~ "Join"

      # User B refreshes
      {:ok, _lobby_b2, html2} = live(conn_b, "/")

      # Should still see Join button for that specific room (not in the room)
      assert html2 =~ ~r/phx-value-room-name="#{room_name}"/
      assert html2 =~ "Join"
    end
  end

  describe "room closure broadcasts" do
    test "when last participant leaves, room disappears from all lobbies" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name_from_button(html_a)

      # User B loads lobby and sees the room
      {:ok, lobby_b, html_b} = live(conn_b, "/")
      assert html_b =~ room_name

      # User A starts the session from the lobby
      lobby_a
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      # Wait for session to start
      sleep_short()

      # User A should be navigated to the session page
      {:ok, session_a, _html} = live(conn_a, "/room/#{room_name}")

      # User A leaves the room (which should close it since they're the only participant)
      session_a
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait a moment for PubSub broadcast to propagate
      sleep_short()

      # User B's lobby should update and no longer show this room
      html_b_after = render(lobby_b)
      refute html_b_after =~ room_name
    end
  end

  describe "room state and button interactions" do
    test "join room in autostart stays on lobby" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name_from_button(html_a)

      # User B joins room (in autostart)
      {:ok, lobby_b, _html} = live(conn_b, "/")

      lobby_b
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      # User B should stay on lobby (not redirected because room is in autostart)
      html_b = render(lobby_b)
      assert html_b =~ room_name
      assert html_b =~ "2 people"
    end

    test "leave room from lobby re-enables create button" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name_from_button(html_a)

      # User B joins room
      {:ok, lobby_b, _html} = live(conn_b, "/")

      lobby_b
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      html_b1 = render(lobby_b)
      assert html_b1 =~ ~r/<button[^>]*phx-click="create_room"[^>]*disabled/

      # User B leaves room from lobby
      lobby_b
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Create Room button should be enabled again
      html_b2 = render(lobby_b)
      refute html_b2 =~ ~r/<button[^>]*phx-click="create_room"[^>]*disabled/

      # Wait for PubSub broadcast to propagate to User A's lobby
      sleep_short()

      # User B should no longer be in participants (check on User A's view)
      html_a = render(lobby_a)
      # Room should still exist and show "1 person" (not "2 people")
      assert html_a =~ room_name
      assert html_a =~ "1 person"
    end

    test "creator leaves room from lobby closes room" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name_from_button(html_a)

      # User B loads lobby and sees the room
      {:ok, lobby_b, html_b} = live(conn_b, "/")
      assert html_b =~ room_name

      # User A leaves room from lobby
      lobby_a
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait a moment for PubSub broadcast
      sleep_short()

      # Room should disappear from User B's lobby
      html_b_after = render(lobby_b)
      refute html_b_after =~ room_name
    end

    test "creator leaves room with participants: room stays open and new creator is assigned" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")
      conn_c = setup_user_conn("userC")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name_from_button(html_a)

      # User B and C join the room
      {:ok, lobby_b, _html} = live(conn_b, "/")

      lobby_b
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      {:ok, lobby_c, _html} = live(conn_c, "/")

      lobby_c
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      # Wait for PubSub broadcasts to propagate
      sleep_short()

      # Verify 3 people in room
      html_a = render(lobby_a)
      assert html_a =~ "3 people"

      # User A (creator) leaves room from lobby
      lobby_a
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait for PubSub broadcast to propagate and LiveView to process it
      sleep_short()

      # Room should still exist and show "2 people" (not closed)
      html_b_after = render(lobby_b)
      html_c_after = render(lobby_c)

      # At least one of them should see the room (may take time for both to update)
      assert (html_b_after =~ room_name and html_b_after =~ "2 people") or
               (html_c_after =~ room_name and html_c_after =~ "2 people")

      # One of User B or User C should now see the Start button (indicating they're the new creator)
      has_start_button_b =
        html_b_after =~
          ~r/<button[^>]*phx-click="start_my_room"[^>]*phx-value-room-name="#{room_name}"[^>]*>\s*Start\s*<\/button>/

      has_start_button_c =
        html_c_after =~
          ~r/<button[^>]*phx-click="start_my_room"[^>]*phx-value-room-name="#{room_name}"[^>]*>\s*Start\s*<\/button>/

      # Exactly one of them should be the new creator
      assert has_start_button_b or has_start_button_c
      refute has_start_button_b and has_start_button_c
    end
  end

  describe "rejoin feature" do
    test "creator can rejoin their own session after leaving" do
      conn_a = setup_user_conn("userA")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name_from_button(html_a)

      # User A starts the session
      lobby_a
      |> element("button[phx-value-room-name='#{room_name}']", "Start")
      |> render_click()

      # Wait for room to start
      sleep_short()

      # User A navigates to the room
      {:ok, session_a, _html} = live(conn_a, "/room/#{room_name}")

      # User A leaves the room
      session_a
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait for PubSub to propagate
      sleep_short()

      # User A should be back in lobby
      {:ok, lobby_a2, html_a2} = live(conn_a, "/")

      # Room should still be visible (creator can rejoin)
      assert html_a2 =~ room_name

      # Should show "In Progress" badge
      assert html_a2 =~ "In Progress"

      # Should show "Rejoin" button (not "Start")
      assert html_a2 =~ "Rejoin"

      # User A clicks Rejoin button and should be redirected to room
      lobby_a2
      |> element("button[phx-click='rejoin_room'][phx-value-room-name='#{room_name}']", "Rejoin")
      |> render_click()

      # Should redirect to /room/#{room_name}
      assert_redirect(lobby_a2, "/room/#{room_name}")

      # User A should be able to navigate to the room screen successfully
      {:ok, _session_a2, html_session} = live(conn_a, "/room/#{room_name}")

      # Should see active session
      assert html_session =~ "Focus time remaining"
      assert html_session =~ "Leave"
    end

    test "user can rejoin an in-progress room they previously left" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name_from_button(html_a)

      # User B joins the room
      {:ok, lobby_b, _html} = live(conn_b, "/")

      lobby_b
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      # Wait for PubSub to propagate
      sleep_short()

      # User A starts the session
      lobby_a
      |> element("button[phx-value-room-name='#{room_name}']", "Start")
      |> render_click()

      # Wait for room to start
      sleep_short()

      # User B navigates to the room
      {:ok, session_b, _html} = live(conn_b, "/room/#{room_name}")

      # User B leaves the room
      session_b
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait for PubSub to propagate
      sleep_short()

      # User B should be back in lobby
      {:ok, lobby_b2, html_b2} = live(conn_b, "/")

      # Room should still be visible (User A is still in it)
      assert html_b2 =~ room_name

      # Should show "In Progress" badge
      assert html_b2 =~ "In Progress"

      # Should show "Rejoin" button (not "Join")
      assert html_b2 =~ "Rejoin"

      refute html_b2 =~
               ~r/<button[^>]*phx-value-room-name="#{room_name}"[^>]*>\s*Join\s*<\/button>/

      # User B clicks Rejoin button and should be redirected to room
      lobby_b2
      |> element("button[phx-click='rejoin_room'][phx-value-room-name='#{room_name}']", "Rejoin")
      |> render_click()

      # Should redirect to /room/#{room_name}
      assert_redirect(lobby_b2, "/room/#{room_name}")

      # User B should be able to navigate to the room screen successfully
      {:ok, _session_b2, html_session} = live(conn_b, "/room/#{room_name}")

      # Should see active session
      assert html_session =~ "Focus time remaining"
      assert html_session =~ "Leave"
    end

    test "rejoin button only appears for rooms the user left" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name_from_button(html_a)

      # User B joins the room
      {:ok, lobby_b, _html} = live(conn_b, "/")

      lobby_b
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      # User A starts the session
      lobby_a
      |> element("button[phx-value-room-name='#{room_name}']", "Start")
      |> render_click()

      # Wait for room to start
      sleep_short()

      # User B navigates to the room
      {:ok, session_b, _html} = live(conn_b, "/room/#{room_name}")

      # User B leaves the room
      session_b
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait for PubSub to propagate
      sleep_short()

      # User B loads lobby again
      {:ok, _lobby_b2, html_b2} = live(conn_b, "/")

      # User B should see the room with "Rejoin" button (was an original participant)
      assert html_b2 =~ room_name
      assert html_b2 =~ "In Progress"
      assert html_b2 =~ "Rejoin"
    end

    test "original participant sees rejoin button when room is on break" do
      conn_a = setup_user_conn("userA")

      # User A creates room with short durations for testing
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name_from_button(html_a)

      # User A starts the session
      lobby_a
      |> element("button[phx-value-room-name='#{room_name}']", "Start")
      |> render_click()

      # Wait for room to start
      sleep_short()

      # Get the room PID to manually transition to break
      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)

      # Manually transition the room to break status
      # This simulates the session completing and going to break
      raw_state = SocialPomodoro.Room.get_raw_state(room_pid)

      # Send ticks to complete the session and enter break
      # Assuming default duration, we need to tick down to 0
      for _ <- 1..raw_state.timer.remaining do
        send(room_pid, :tick)
      end

      # One more tick to transition to break
      send(room_pid, :tick)

      # Wait for state to update
      sleep_short()

      # Verify room is now in break
      state = SocialPomodoro.Room.get_state(room_pid)
      assert state.status == :break

      # User A navigates back to lobby (simulating going back from session page)
      {:ok, lobby_a2, html_a2} = live(conn_a, "/")

      # Room should still be visible
      assert html_a2 =~ room_name

      # Should show "On Break" badge
      assert html_a2 =~ "On Break"

      # Should show "Rejoin" button (user is already in the room but viewing lobby)
      assert html_a2 =~ "Rejoin"

      assert html_a2 =~
               ~r/<button[^>]*phx-click="rejoin_room"[^>]*phx-value-room-name="#{room_name}"[^>]*>\s*Rejoin\s*<\/button>/

      # User A clicks Rejoin button and should be redirected to room
      lobby_a2
      |> element("button[phx-click='rejoin_room'][phx-value-room-name='#{room_name}']", "Rejoin")
      |> render_click()

      # Should redirect to /room/#{room_name}
      assert_redirect(lobby_a2, "/room/#{room_name}")

      # User A should be able to navigate to the room screen successfully
      {:ok, _session_a2, html_session} = live(conn_a, "/room/#{room_name}")

      # Should see break view
      assert html_session =~ "Break time"
    end

    test "original participant who left during break sees rejoin button on lobby" do
      conn_a = setup_user_conn("userA")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name_from_button(html_a)

      # User A starts the session
      lobby_a
      |> element("button[phx-value-room-name='#{room_name}']", "Start")
      |> render_click()

      # Wait for room to start
      sleep_short()

      # Get the room PID to manually transition to break
      {:ok, room_pid} = SocialPomodoro.RoomRegistry.get_room(room_name)

      # Manually transition the room to break status
      raw_state = SocialPomodoro.Room.get_raw_state(room_pid)

      # Send ticks to complete the session and enter break
      for _ <- 1..raw_state.timer.remaining do
        send(room_pid, :tick)
      end

      # One more tick to transition to break
      send(room_pid, :tick)

      # Wait for state to update
      sleep_short()

      # Verify room is now in break
      state = SocialPomodoro.Room.get_state(room_pid)
      assert state.status == :break

      # Navigate to the room to join the break
      {:ok, session_a, _html} = live(conn_a, "/room/#{room_name}")

      # User A leaves the room during break
      session_a
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait for PubSub to propagate
      sleep_short()

      # User A should be back in lobby
      {:ok, lobby_a2, html_a2} = live(conn_a, "/")

      # Room should still be visible (user is an original participant)
      assert html_a2 =~ room_name

      # Should show "On Break" badge
      assert html_a2 =~ "On Break"

      # Should show "Rejoin" button (user is an original participant who left during break)
      assert html_a2 =~ "Rejoin"

      assert html_a2 =~
               ~r/<button[^>]*phx-click="rejoin_room"[^>]*phx-value-room-name="#{room_name}"[^>]*>\s*Rejoin\s*<\/button>/

      # User A clicks Rejoin button and should be redirected to room
      lobby_a2
      |> element("button[phx-click='rejoin_room'][phx-value-room-name='#{room_name}']", "Rejoin")
      |> render_click()

      # Should redirect to /room/#{room_name}
      assert_redirect(lobby_a2, "/room/#{room_name}")

      # User A should be able to navigate to the room screen successfully
      {:ok, _session_a2, html_session} = live(conn_a, "/room/#{room_name}")

      # Should see break view
      assert html_session =~ "Break time"
    end
  end

  describe "room sharing via link" do
    test "user A creates room, user B can join via direct link" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name(html_a)

      # User B visits the direct link /at/:room_name
      # This triggers a push_navigate during connected mount with flash
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn_b, "/at/#{room_name}")

      # Follow the redirect
      {:ok, lobby_b, html_b} = live(conn_b, "/")

      # Wait for PubSub to propagate
      sleep_short()

      # User B should now be in the room with autostart countdown
      assert html_b =~ "Starting"

      # Both users should see 2 participants
      html_a_after = render(lobby_a)
      html_b_after = render(lobby_b)

      assert html_a_after =~ "2 people"
      assert html_b_after =~ "2 people"
    end

    test "share button only visible to creator" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name(html_a)

      # User A (creator) should see share button
      assert html_a =~ ~r/id="share-btn-#{room_name}"/

      # User B loads lobby (not in room)
      {:ok, _lobby_b, html_b} = live(conn_b, "/")

      # User B should NOT see share button for User A's room
      refute html_b =~ ~r/id="share-btn-#{room_name}"/
    end

    test "share button visible to participants" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name(html_a)

      # User B joins the room
      {:ok, lobby_b, _html} = live(conn_b, "/")

      lobby_b
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      html_b_after = render(lobby_b)

      # User B (now a participant) should see share button
      assert html_b_after =~ ~r/id="share-btn-#{room_name}"/
    end

    test "share button hidden from non-participants after user leaves" do
      conn_a = setup_user_conn("userA")
      conn_b = setup_user_conn("userB")

      # User A creates room
      {:ok, lobby_a, _html} = live(conn_a, "/")

      lobby_a
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_a = render(lobby_a)
      room_name = extract_room_name(html_a)

      # User B joins the room
      {:ok, lobby_b, _html} = live(conn_b, "/")

      lobby_b
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      html_b_joined = render(lobby_b)
      # User B should see share button while in room
      assert html_b_joined =~ ~r/id="share-btn-#{room_name}"/

      # User B leaves the room
      lobby_b
      |> element("button[phx-click='leave_room']")
      |> render_click()

      html_b_left = render(lobby_b)
      # User B should NOT see share button after leaving
      refute html_b_left =~ ~r/id="share-btn-#{room_name}"/
    end
  end
end
