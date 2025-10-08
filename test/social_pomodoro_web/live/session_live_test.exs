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
end
