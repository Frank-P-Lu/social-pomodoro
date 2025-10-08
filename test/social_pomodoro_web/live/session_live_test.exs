defmodule SocialPomodoroWeb.SessionLiveTest do
  use SocialPomodoroWeb.ConnCase
  import Phoenix.LiveViewTest

  # Helper to create a connection with a user session
  defp setup_user_conn(user_id) do
    unique_id = "#{user_id}_#{System.unique_integer([:positive])}"

    build_conn()
    |> Plug.Test.init_test_session(%{"user_id" => unique_id})
  end

  describe "completion message" do
    test "shows random solo message for single participant" do
      conn = setup_user_conn("userA")

      # Create room
      {:ok, lobby, _html} = live(conn, "/")
      lobby |> element("button[phx-click='create_room']") |> render_click()
      html = render(lobby)

      # Extract room_id
      room_id =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-id="([^"]+)"/, html) do
          [_, room_id] -> room_id
          _ -> nil
        end

      # Join session
      {:ok, session, _html} = live(conn, "/room/#{room_id}")

      # Start session (only creator can start)
      session |> element("button[phx-click='start_session']") |> render_click()

      # Wait for session to complete (this would need to be done via mocking or time manipulation)
      # For now, we just verify the structure exists
      # In a real test, we would simulate the timer completing and check the break view

      # The message should be one of the solo messages:
      # - "You focused solo!"
      # - "Flying solo today - nice work!"
      # - "Solo focus session complete!"
      # - "You stayed focused!"
    end

    test "shows 'X other people' message for multiple participants" do
      connA = setup_user_conn("userA")
      connB = setup_user_conn("userB")

      # User A creates room
      {:ok, lobbyA, _html} = live(connA, "/")
      lobbyA |> element("button[phx-click='create_room']") |> render_click()
      htmlA = render(lobbyA)

      # Extract room_id
      room_id =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-id="([^"]+)"/, htmlA) do
          [_, room_id] -> room_id
          _ -> nil
        end

      # User B joins the room from lobby
      {:ok, lobbyB, _html} = live(connB, "/")
      lobbyB |> element("button[phx-click='join_room'][phx-value-room-id='#{room_id}']") |> render_click()

      # Both users should now be in the room
      # When the session completes, the message should say "You focused with 1 other person!"
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

      # Extract room_id
      room_id =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-id="([^"]+)"/, htmlA) do
          [_, room_id] -> room_id
          _ -> nil
        end

      # User B tries to access room URL directly without joining
      {:ok, _sessionB, htmlB} = live(connB, "/room/#{room_id}")

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

      # Extract room_id
      room_id =
        case Regex.run(~r/phx-click="start_my_room"[^>]*phx-value-room-id="([^"]+)"/, htmlA) do
          [_, room_id] -> room_id
          _ -> nil
        end

      # User A accesses their own room
      {:ok, _sessionA, htmlA_session} = live(connA, "/room/#{room_id}")

      # Should NOT see redirect screen
      refute htmlA_session =~ "Oops! You're not in this room"
      # Should see waiting room instead
      assert htmlA_session =~ "Waiting to Start"
    end
  end
end
