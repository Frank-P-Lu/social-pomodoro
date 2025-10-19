defmodule SocialPomodoroWeb.LobbyLiveTest do
  use SocialPomodoroWeb.ConnCase
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

  describe "timer defaults" do
    test "defaults to configured duration, cycles, and break" do
      conn = setup_user_conn("defaults_user")
      {:ok, lobby, _html} = live(conn, "/")

      html = render(lobby)

      assert html =~ ~r/phx-value-minutes="25"[^>]*btn-primary/
      assert html =~ ~r/phx-value-cycles="4"[^>]*btn-primary/
      assert html =~ ~r/phx-value-minutes="5"[^>]*btn-primary/
      refute html =~ "No breaks for a single pomodoro."
    end

    test "selecting a duration applies configured defaults" do
      conn = setup_user_conn("duration_defaults_user")
      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='set_duration'][phx-value-minutes='50']")
      |> render_click()

      html = render(lobby)

      assert html =~ ~r/phx-value-minutes="50"[^>]*btn-primary/
      assert html =~ ~r/phx-value-cycles="2"[^>]*btn-primary/
      assert html =~ ~r/phx-value-minutes="10"[^>]*btn-primary/
      refute html =~ "No breaks for a single pomodoro."

      lobby
      |> element("button[phx-click='set_duration'][phx-value-minutes='75']")
      |> render_click()

      html = render(lobby)

      assert html =~ ~r/phx-value-minutes="75"[^>]*btn-primary/
      assert html =~ ~r/phx-value-cycles="1"[^>]*btn-primary/
      assert html =~ ~r/phx-value-minutes="5"[^>]*btn-primary/
      assert html =~ "No breaks for a single pomodoro."
      assert html =~ ~r/phx-value-minutes="10"[^>]*disabled/
    end

    test "single cycle selection locks break duration" do
      conn = setup_user_conn("single_cycle_user")
      {:ok, lobby, _html} = live(conn, "/")

      lobby
      |> element("button[phx-click='set_cycles'][phx-value-cycles='1']")
      |> render_click()

      html = render(lobby)

      assert html =~ ~r/phx-value-cycles="1"[^>]*btn-primary/
      assert html =~ ~r/phx-value-minutes="5"[^>]*btn-primary/
      assert html =~ "No breaks for a single pomodoro."
      assert html =~ ~r/phx-value-minutes="10"[^>]*disabled/

      html = render(lobby)

      assert html =~ ~r/phx-value-minutes="5"[^>]*btn-primary/
      assert html =~ "No breaks for a single pomodoro."
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
  end

  describe "empty state" do
    test "displays friendly empty state message when no rooms available" do
      # Wait for any existing rooms from other tests to be cleaned up
      # Rooms are cleaned up when they become empty, so we need to wait a bit
      # for any lingering room processes to terminate
      sleep_short()

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
      sleep_short()

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

  describe "room sharing via link" do
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

  describe "room sorting" do
    test "rooms are sorted by: user-created, open, then in-progress" do
      # Set up three users
      conn_creator = setup_user_conn("creator")
      conn_other1 = setup_user_conn("other1")
      conn_other2 = setup_user_conn("other2")

      # User other1 creates an open room (autostart)
      {:ok, lobby_other1, _html} = live(conn_other1, "/")

      lobby_other1
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_other1 = render(lobby_other1)
      room_other1 = extract_room_name_from_button(html_other1)

      # User other2 creates a room and starts it (in-progress)
      {:ok, lobby_other2, _html} = live(conn_other2, "/")

      lobby_other2
      |> element("button[phx-click='create_room']")
      |> render_click()

      html_other2 = render(lobby_other2)
      room_other2 = extract_room_name_from_button(html_other2)

      # Start the second room to make it in-progress
      lobby_other2
      |> element("button[phx-value-room-name='#{room_other2}']", "Start")
      |> render_click()

      # Wait for room to start
      sleep_short()

      # Now creator creates their own room
      {:ok, lobby_creator, _html} = live(conn_creator, "/")

      lobby_creator
      |> element("button[phx-click='create_room']")
      |> render_click()

      # Wait for PubSub to propagate
      sleep_short()

      html_creator = render(lobby_creator)
      room_creator = extract_room_name_from_button(html_creator)

      # Extract all room names in order from the HTML
      # The HTML should show rooms in this order:
      # 1. room_creator (user-created room)
      # 2. room_other1 (open/autostart room)
      # 3. room_other2 should NOT be visible because other2 is in an active session
      #    and creator is not a session participant

      # Find positions of each room name in the HTML
      match_creator = :binary.match(html_creator, room_creator)
      match_other1 = :binary.match(html_creator, room_other1)
      match_other2 = :binary.match(html_creator, room_other2)

      assert match_creator != :nomatch, "Creator room should be visible: #{room_creator}"
      assert match_other1 != :nomatch, "Other1 room should be visible: #{room_other1}"

      # Room other2 should not be visible since it's in an active session
      # and creator is not a session participant
      assert match_other2 == :nomatch,
             "In-progress room should not be visible to non-participants: #{room_other2}"

      pos_creator = elem(match_creator, 0)
      pos_other1 = elem(match_other1, 0)

      # Assert that creator's room appears first
      assert pos_creator < pos_other1,
             "User-created room should appear before open rooms"
    end
  end
end
