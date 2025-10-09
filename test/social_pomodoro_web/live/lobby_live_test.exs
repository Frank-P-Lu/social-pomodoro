defmodule SocialPomodoroWeb.LobbyLiveTest do
  use SocialPomodoroWeb.ConnCase
  import Phoenix.LiveViewTest

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

  describe "single user flow" do
    test "user can create room, start it, and navigate to session" do
      conn = setup_user_conn("user1")
      {:ok, lobby, _html} = live(conn, "/")

      # Create room
      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      # Room should appear in lobby with Start button
      html = render(lobby)
      assert html =~ "Start"
      room_name = extract_room_name_from_button(html)

      # Click Start and verify navigation
      lobby
      |> element("button", "Start")
      |> render_click()

      assert_redirect(lobby, "/room/#{room_name}")
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

      # User B joins the specific room using phx-value-room-name
      lobbyB
      |> element("button[phx-value-room-name='#{room_name}']")
      |> render_click()

      # Both lobbies should now show 2 participants
      htmlA = render(lobbyA)
      htmlB = render(lobbyB)

      # Both should see "2 people" for the room
      assert htmlA =~ "2 people"
      assert htmlB =~ "2 people"

      # User B should see "Waiting for host..." somewhere in the page
      assert htmlB =~ "Waiting for host..."
      # And the room_name should exist in a button (no longer Join for this room)
      refute htmlB =~ ~r/<button[^>]*phx-click="join_room"[^>]*phx-value-room-name="#{room_name}"/

      # User A should see "Start" button for their room (with room_name attribute)
      assert htmlA =~ ~r/phx-value-room-name="#{room_name}"/
      assert htmlA =~ "Start"

      # User A starts the session
      lobbyA
      |> element("button[phx-value-room-name='#{room_name}']", "Start")
      |> render_click()

      # Both should navigate to the same room
      assert_redirect(lobbyA, "/room/#{room_name}")
      assert_redirect(lobbyB, "/room/#{room_name}")
    end
  end

  describe "refresh persistence" do
    test "creator can see Start button after refresh" do
      conn = setup_user_conn("user1")

      # Create room
      {:ok, lobby1, _html} = live(conn, "/")

      lobby1
      |> element("button[phx-click='create_room']")
      |> render_click()

      html1 = render(lobby1)
      assert html1 =~ "Start"

      # Simulate refresh by remounting with same session
      {:ok, _lobby2, html2} = live(conn, "/")

      # Should still see Start button
      assert html2 =~ "Start"
    end

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
      assert html1 =~ "Waiting for host..."

      # User B refreshes
      {:ok, _lobbyB2, html2} = live(connB, "/")

      # Should still see "Waiting for host..." (not "Join")
      assert html2 =~ "Waiting for host..."
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

      # User A navigates to the room page
      {:ok, sessionA, _html} = live(connA, "/room/#{room_name}")

      # User A leaves the room (which should close it since they're the only participant)
      sessionA
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait a moment for PubSub broadcast to propagate
      Process.sleep(50)

      # User B's lobby should update and no longer show this room
      htmlB_after = render(lobbyB)
      refute htmlB_after =~ room_name
    end
  end

  describe "room state and button interactions" do
    test "create room disables create button" do
      conn = setup_user_conn("user1")
      {:ok, lobby, _html} = live(conn, "/")

      # Create room
      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      # Create Room button should now be disabled
      html = render(lobby)
      assert html =~ ~r/<button[^>]*phx-click="create_room"[^>]*disabled/
    end

    test "join room disables create button" do
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

      # User B's Create Room button should be disabled
      htmlB = render(lobbyB)
      assert htmlB =~ ~r/<button[^>]*phx-click="create_room"[^>]*disabled/
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
      Process.sleep(100)

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
      Process.sleep(50)

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
      Process.sleep(50)

      # Verify 3 people in room
      htmlA = render(lobbyA)
      assert htmlA =~ "3 people"

      # User A (creator) leaves room from lobby
      lobbyA
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait for PubSub broadcast to propagate and LiveView to process it
      Process.sleep(50)

      # Room should still exist and show "2 people" (not closed)
      htmlB_after = render(lobbyB)
      htmlC_after = render(lobbyC)

      # At least one of them should see the room (may take time for both to update)
      assert (htmlB_after =~ room_name and htmlB_after =~ "2 people") or
               (htmlC_after =~ room_name and htmlC_after =~ "2 people")

      # One of User B or User C should now see the Start button (indicating they're the new creator)
      has_start_button_B =
        htmlB_after =~
          ~r/<button[^>]*phx-click="start_my_room"[^>]*phx-value-room-name="#{room_name}"[^>]*>\s*Start\s*<\/button>/

      has_start_button_C =
        htmlC_after =~
          ~r/<button[^>]*phx-click="start_my_room"[^>]*phx-value-room-name="#{room_name}"[^>]*>\s*Start\s*<\/button>/

      # Exactly one of them should be the new creator
      assert has_start_button_B or has_start_button_C
      refute has_start_button_B and has_start_button_C
    end
  end

  describe "rejoin feature" do
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
      Process.sleep(50)

      # User A starts the session
      lobbyA
      |> element("button[phx-value-room-name='#{room_name}']", "Start")
      |> render_click()

      # Wait for room to start
      Process.sleep(50)

      # User B navigates to the room
      {:ok, sessionB, _html} = live(connB, "/room/#{room_name}")

      # User B leaves the room
      sessionB
      |> element("button[phx-click='leave_room']")
      |> render_click()

      # Wait for PubSub to propagate
      Process.sleep(50)

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
      connC = setup_user_conn("userC")

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
      Process.sleep(50)

      # User C loads lobby (never joined this room)
      {:ok, _lobbyC, htmlC} = live(connC, "/")

      # User C should see the room as "In Progress" but NO button to join/rejoin
      assert htmlC =~ room_name
      assert htmlC =~ "In Progress"
      refute htmlC =~ "Rejoin"
      refute htmlC =~ ~r/<button[^>]*phx-value-room-name="#{room_name}"/
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
      {:ok, _lobbyB, htmlB} = live(connB, "/")

      # User B should now be in the room
      assert htmlB =~ "Waiting for host..."

      # Both users should see 2 participants
      htmlA_after = render(lobbyA)

      assert htmlA_after =~ "2 people"
      assert htmlB =~ "2 people"
    end

    test "visiting non-existent room link shows error message" do
      conn = setup_user_conn("user1")

      # Visit a link to a room that doesn't exist
      # This triggers a push_navigate during connected mount with error flash
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/at/Nonexistent-Room-Name")
    end

    test "share button copies correct link format" do
      conn = setup_user_conn("user1")

      # Create room
      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)
      room_name = extract_room_name(html)

      # Verify share button exists with correct room_name data attribute
      assert html =~ ~r/id="share-btn-#{room_name}"/
      assert html =~ ~r/data-room-name="#{Regex.escape(room_name)}"/
      assert html =~ ~r/phx-hook="CopyToClipboard"/
    end
  end

  describe "empty state" do
    test "displays friendly empty state message when no rooms available" do
      # Wait for any existing rooms from other tests to be cleaned up
      # Rooms are cleaned up when they become empty, so we need to wait a bit
      # for any lingering room processes to terminate
      Process.sleep(50)

      # Set up a unique user for this test
      user_id = "empty_state_test_user_#{System.unique_integer([:positive])}"
      conn = setup_user_conn(user_id)

      # Clean up any lingering rooms by making participants leave
      existing_rooms = SocialPomodoro.RoomRegistry.list_rooms(user_id)

      for room <- existing_rooms do
        # Get all participants and make them leave
        for participant <- room.participants do
          SocialPomodoro.Room.leave(room.name, participant.user_id)
        end
      end

      # Wait a bit more for cleanup to complete
      Process.sleep(50)

      {:ok, _lobby, html} = live(conn, "/")

      # Should see the friendly empty state message
      assert html =~ "No one is here yet"
    end

    test "does not display empty state when rooms are available" do
      conn = setup_user_conn("user1")
      {:ok, lobby, _html} = live(conn, "/")

      # Create a room
      lobby
      |> element("button[phx-click='create_room']")
      |> render_click()

      html = render(lobby)

      # Should NOT see the empty state message
      refute html =~ "No one is here yet"
    end
  end
end
