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
      {:ok, lobbyA, _html} = live(conn1, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name_from_button(htmlA)

      # User B loads lobby and sees the room
      {:ok, lobbyB, htmlB} = live(conn2, "/")
      assert htmlB =~ room_name

      # User B joins the specific room using phx-value-room-name (room is in autostart)
      lobbyB
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      # User B should stay on lobby (room is in autostart, not active/break)
      htmlB = render(lobbyB)
      htmlA = render(lobbyA)

      # Both should see "2 people" for the room
      assert htmlA =~ "2 people"
      assert htmlB =~ "2 people"

      # User A should see "Start" button for their room (with room_name attribute)
      assert htmlA =~ ~r/phx-value-room-name="#{room_name}"/
      assert htmlA =~ "Start"

      # User A starts the session
      lobbyA
      |> element("button[phx-value-room-name='#{room_name}']", "Start")
      |> render_click()

      # User A should navigate to the room
      assert_redirect(lobbyA, "/room/#{room_name}")
    end
  end

  describe "refresh persistence" do
    test "participant sees 'Waiting for host...' after refresh" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name_from_button(htmlA)

      # User B joins
      {:ok, lobbyB1, _html} = live(connB, "/")

      lobbyB1
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      html1 = render(lobbyB1)
      assert html1 =~ "Starting"

      # User B refreshes
      {:ok, _lobbyB2, html2} = live(connB, "/")

      # Should still see "Starting" countdown (not "Join")
      assert html2 =~ "Starting"
      refute html2 =~ ~r/<button[^>]*phx-value-room-name="#{room_name}"[^>]*>Join<\/button>/
    end

    test "non-participant still sees Join button after refresh" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name_from_button(htmlA)

      # User B loads lobby but doesn't join
      {:ok, _lobbyB1, html1} = live(connB, "/")
      assert html1 =~ "Join"

      # User B refreshes
      {:ok, _lobbyB2, html2} = live(connB, "/")

      # Should still see Join button for that specific room (not in the room)
      assert html2 =~ ~r/phx-value-room-name="#{room_name}"/
      assert html2 =~ "Join"
    end
  end

  describe "room closure broadcasts" do
    test "when last participant leaves, room disappears from all lobbies" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name_from_button(htmlA)

      # User B loads lobby and sees the room
      {:ok, lobbyB, htmlB} = live(connB, "/")
      assert htmlB =~ room_name

      # User A starts the session from the lobby
      lobbyA
      |> element("button[phx-click='start_my_room']")
      |> render_click()

      # Wait for session to start
      sleep_short()

      # User A should be navigated to the session page
      {:ok, sessionA, _html} = live(connA, "/room/#{room_name}")

      # User A leaves the room (which should close it since they're the only participant)
      sessionA
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait a moment for PubSub broadcast to propagate
      sleep_short()

      # User B's lobby should update and no longer show this room
      htmlB_after = render(lobbyB)
      refute htmlB_after =~ room_name
    end
  end

  describe "room state and button interactions" do
    test "join room in autostart stays on lobby" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name_from_button(htmlA)

      # User B joins room (in autostart)
      {:ok, lobbyB, _html} = live(connB, "/")

      lobbyB
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      # User B should stay on lobby (not redirected because room is in autostart)
      htmlB = render(lobbyB)
      assert htmlB =~ room_name
      assert htmlB =~ "2 people"
    end

    test "leave room from lobby re-enables create button" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name_from_button(htmlA)

      # User B joins room
      {:ok, lobbyB, _html} = live(connB, "/")

      lobbyB
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      htmlB1 = render(lobbyB)
      assert htmlB1 =~ ~r/<button[^>]*phx-click="create_room"[^>]*disabled/

      # User B leaves room from lobby
      lobbyB
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Create Room button should be enabled again
      htmlB2 = render(lobbyB)
      refute htmlB2 =~ ~r/<button[^>]*phx-click="create_room"[^>]*disabled/

      # Wait for PubSub broadcast to propagate to User A's lobby
      sleep_short()

      # User B should no longer be in participants (check on User A's view)
      htmlA = render(lobbyA)
      # Room should still exist and show "1 person" (not "2 people")
      assert htmlA =~ room_name
      assert htmlA =~ "1 person"
    end

    test "creator leaves room from lobby closes room" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name_from_button(htmlA)

      # User B loads lobby and sees the room
      {:ok, lobbyB, htmlB} = live(connB, "/")
      assert htmlB =~ room_name

      # User A leaves room from lobby
      lobbyA
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait a moment for PubSub broadcast
      sleep_short()

      # Room should disappear from User B's lobby
      htmlB_after = render(lobbyB)
      refute htmlB_after =~ room_name
    end

    test "creator leaves room with participants: room stays open and new creator is assigned" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")
      connC = setup_user_conn("userC")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name_from_button(htmlA)

      # User B and C join the room
      {:ok, lobbyB, _html} = live(connB, "/")

      lobbyB
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      {:ok, lobbyC, _html} = live(connC, "/")

      lobbyC
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      # Wait for PubSub broadcasts to propagate
      sleep_short()

      # Verify 3 people in room
      htmlA = render(lobbyA)
      assert htmlA =~ "3 people"

      # User A (creator) leaves room from lobby
      lobbyA
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait for PubSub broadcast to propagate and LiveView to process it
      sleep_short()

      # Room should still exist and show "2 people" (not closed)
      htmlB_after = render(lobbyB)
      htmlC_after = render(lobbyC)

      # At least one of them should see the room (may take time for both to update)
      assert (htmlB_after =~ room_name and htmlB_after =~ "2 people") or
               (htmlC_after =~ room_name and htmlC_after =~ "2 people")

      # One of User B or User C should now see the Start Now button (indicating they're the new creator)
      has_start_button_B =
        htmlB_after =~
          ~r/<button[^>]*phx-click="start_my_room"[^>]*phx-value-room-name="#{room_name}"[^>]*>\s*Start Now\s*<\/button>/

      has_start_button_C =
        htmlC_after =~
          ~r/<button[^>]*phx-click="start_my_room"[^>]*phx-value-room-name="#{room_name}"[^>]*>\s*Start Now\s*<\/button>/

      # Exactly one of them should be the new creator
      assert has_start_button_B or has_start_button_C
      refute has_start_button_B and has_start_button_C
    end
  end

  describe "rejoin feature" do
    test "creator can rejoin their own session after leaving" do
      connA = setup_user_conn("userA")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name_from_button(htmlA)

      # User A starts the session
      lobbyA
      |> element("button[phx-value-room-name='#{room_name}']", "Start")
      |> render_click()

      # Wait for room to start
      sleep_short()

      # User A navigates to the room
      {:ok, sessionA, _html} = live(connA, "/room/#{room_name}")

      # User A leaves the room
      sessionA
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait for PubSub to propagate
      sleep_short()

      # User A should be back in lobby
      {:ok, lobbyA2, htmlA2} = live(connA, "/")

      # Room should still be visible (creator can rejoin)
      assert htmlA2 =~ room_name

      # Should show "In Progress" badge
      assert htmlA2 =~ "In Progress"

      # Should show "Rejoin" button (not "Start")
      assert htmlA2 =~ "Rejoin"

      # User A clicks Rejoin button and should be redirected to room
      lobbyA2
      |> element("button[phx-click='rejoin_room'][phx-value-room-name='#{room_name}']", "Rejoin")
      |> render_click()

      # Should redirect to /room/#{room_name}
      assert_redirect(lobbyA2, "/room/#{room_name}")

      # User A should be able to navigate to the room screen successfully
      {:ok, _sessionA2, htmlSession} = live(connA, "/room/#{room_name}")

      # Should see active session
      assert htmlSession =~ "Focus time remaining"
      assert htmlSession =~ "Leave"
    end

    test "user can rejoin an in-progress room they previously left" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name_from_button(htmlA)

      # User B joins the room
      {:ok, lobbyB, _html} = live(connB, "/")

      lobbyB
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      # Wait for PubSub to propagate
      sleep_short()

      # User A starts the session
      lobbyA
      |> element("button[phx-value-room-name='#{room_name}']", "Start")
      |> render_click()

      # Wait for room to start
      sleep_short()

      # User B navigates to the room
      {:ok, sessionB, _html} = live(connB, "/room/#{room_name}")

      # User B leaves the room
      sessionB
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait for PubSub to propagate
      sleep_short()

      # User B should be back in lobby
      {:ok, lobbyB2, htmlB2} = live(connB, "/")

      # Room should still be visible (User A is still in it)
      assert htmlB2 =~ room_name

      # Should show "In Progress" badge
      assert htmlB2 =~ "In Progress"

      # Should show "Rejoin" button (not "Join")
      assert htmlB2 =~ "Rejoin"

      refute htmlB2 =~
               ~r/<button[^>]*phx-value-room-name="#{room_name}"[^>]*>\s*Join\s*<\/button>/

      # User B clicks Rejoin button and should be redirected to room
      lobbyB2
      |> element("button[phx-click='rejoin_room'][phx-value-room-name='#{room_name}']", "Rejoin")
      |> render_click()

      # Should redirect to /room/#{room_name}
      assert_redirect(lobbyB2, "/room/#{room_name}")

      # User B should be able to navigate to the room screen successfully
      {:ok, _sessionB2, htmlSession} = live(connB, "/room/#{room_name}")

      # Should see active session
      assert htmlSession =~ "Focus time remaining"
      assert htmlSession =~ "Leave"
    end

    test "rejoin button only appears for rooms the user left" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name_from_button(htmlA)

      # User B joins the room
      {:ok, lobbyB, _html} = live(connB, "/")

      lobbyB
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      # User A starts the session
      lobbyA
      |> element("button[phx-value-room-name='#{room_name}']", "Start")
      |> render_click()

      # Wait for room to start
      sleep_short()

      # User B navigates to the room
      {:ok, sessionB, _html} = live(connB, "/room/#{room_name}")

      # User B leaves the room
      sessionB
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait for PubSub to propagate
      sleep_short()

      # User B loads lobby again
      {:ok, _lobbyB2, htmlB2} = live(connB, "/")

      # User B should see the room with "Rejoin" button (was an original participant)
      assert htmlB2 =~ room_name
      assert htmlB2 =~ "In Progress"
      assert htmlB2 =~ "Rejoin"
    end

    test "original participant sees rejoin button when room is on break" do
      connA = setup_user_conn("userA")

      # User A creates room with short durations for testing
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name_from_button(htmlA)

      # User A starts the session
      lobbyA
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
      {:ok, lobbyA2, htmlA2} = live(connA, "/")

      # Room should still be visible
      assert htmlA2 =~ room_name

      # Should show "On Break" badge
      assert htmlA2 =~ "On Break"

      # Should show "Rejoin" button (user is already in the room but viewing lobby)
      assert htmlA2 =~ "Rejoin"

      assert htmlA2 =~
               ~r/<button[^>]*phx-click="rejoin_room"[^>]*phx-value-room-name="#{room_name}"[^>]*>\s*Rejoin\s*<\/button>/

      # User A clicks Rejoin button and should be redirected to room
      lobbyA2
      |> element("button[phx-click='rejoin_room'][phx-value-room-name='#{room_name}']", "Rejoin")
      |> render_click()

      # Should redirect to /room/#{room_name}
      assert_redirect(lobbyA2, "/room/#{room_name}")

      # User A should be able to navigate to the room screen successfully
      {:ok, _sessionA2, htmlSession} = live(connA, "/room/#{room_name}")

      # Should see break view
      assert htmlSession =~ "Break time"
    end

    test "original participant who left during break sees rejoin button on lobby" do
      connA = setup_user_conn("userA")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name_from_button(htmlA)

      # User A starts the session
      lobbyA
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
      {:ok, sessionA, _html} = live(connA, "/room/#{room_name}")

      # User A leaves the room during break
      sessionA
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait for PubSub to propagate
      sleep_short()

      # User A should be back in lobby
      {:ok, lobbyA2, htmlA2} = live(connA, "/")

      # Room should still be visible (user is an original participant)
      assert htmlA2 =~ room_name

      # Should show "On Break" badge
      assert htmlA2 =~ "On Break"

      # Should show "Rejoin" button (user is an original participant who left during break)
      assert htmlA2 =~ "Rejoin"

      assert htmlA2 =~
               ~r/<button[^>]*phx-click="rejoin_room"[^>]*phx-value-room-name="#{room_name}"[^>]*>\s*Rejoin\s*<\/button>/

      # User A clicks Rejoin button and should be redirected to room
      lobbyA2
      |> element("button[phx-click='rejoin_room'][phx-value-room-name='#{room_name}']", "Rejoin")
      |> render_click()

      # Should redirect to /room/#{room_name}
      assert_redirect(lobbyA2, "/room/#{room_name}")

      # User A should be able to navigate to the room screen successfully
      {:ok, _sessionA2, htmlSession} = live(connA, "/room/#{room_name}")

      # Should see break view
      assert htmlSession =~ "Break time"
    end
  end

  describe "room sharing via link" do
    test "user A creates room, user B can join via direct link" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name(htmlA)

      # User B visits the direct link /at/:room_name
      # This triggers a push_navigate during connected mount with flash
      assert {:error, {:live_redirect, %{to: "/"}}} = live(connB, "/at/#{room_name}")

      # Follow the redirect
      {:ok, lobbyB, htmlB} = live(connB, "/")

      # Wait for PubSub to propagate
      sleep_short()

      # User B should now be in the room with autostart countdown
      assert htmlB =~ "Starting"

      # Both users should see 2 participants
      htmlA_after = render(lobbyA)
      htmlB_after = render(lobbyB)

      assert htmlA_after =~ "2 people"
      assert htmlB_after =~ "2 people"
    end

    test "share button only visible to creator" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name(htmlA)

      # User A (creator) should see share button
      assert htmlA =~ ~r/id="share-btn-#{room_name}"/

      # User B loads lobby (not in room)
      {:ok, _lobbyB, htmlB} = live(connB, "/")

      # User B should NOT see share button for User A's room
      refute htmlB =~ ~r/id="share-btn-#{room_name}"/
    end

    test "share button visible to participants" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name(htmlA)

      # User B joins the room
      {:ok, lobbyB, _html} = live(connB, "/")

      lobbyB
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      htmlB_after = render(lobbyB)

      # User B (now a participant) should see share button
      assert htmlB_after =~ ~r/id="share-btn-#{room_name}"/
    end

    test "share button hidden from non-participants after user leaves" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")

      lobbyA
      |> element("button[phx-click='create_room']")
      |> render_click()

      htmlA = render(lobbyA)
      room_name = extract_room_name(htmlA)

      # User B joins the room
      {:ok, lobbyB, _html} = live(connB, "/")

      lobbyB
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      htmlB_joined = render(lobbyB)
      # User B should see share button while in room
      assert htmlB_joined =~ ~r/id="share-btn-#{room_name}"/

      # User B leaves the room
      lobbyB
      |> element("button[phx-click='leave_room']")
      |> render_click()

      htmlB_left = render(lobbyB)
      # User B should NOT see share button after leaving
      refute htmlB_left =~ ~r/id="share-btn-#{room_name}"/
    end
  end
end
