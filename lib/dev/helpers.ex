defmodule Dev.Helpers do
  @moduledoc """
  Helper functions for development and testing.
  Use these in `iex -S mix phx.server` console.
  """

  @doc """
  Creates a test room for the given username in the specified status.

  ## Examples

      # In iex console:
      Dev.Helpers.create_test_room("BoldTiger14", :break)
      Dev.Helpers.create_test_room("HappyPanda42", :active)

  """
  def create_test_room(username, status \\ :active) do
    unless status in [:autostart, :active, :break] do
      IO.puts("Invalid status: #{status}")
      IO.puts("Valid statuses: :autostart, :active, :break")
      :error
    end

    # Look up user_id by username
    case SocialPomodoro.UserRegistry.find_user_id_by_username(username) do
      {:ok, user_id} ->
        do_create_room(user_id, username, status)

      {:error, :not_found} ->
        all_usernames = SocialPomodoro.UserRegistry.list_all_usernames()

        IO.puts("❌ Username '#{username}' not found!")

        if Enum.empty?(all_usernames) do
          IO.puts("No users registered yet. Visit the app in a browser first.")
        else
          IO.puts("Available usernames:")

          Enum.each(all_usernames, fn name ->
            IO.puts("  - #{name}")
          end)
        end

        :error
    end
  end

  @doc """
  Lists all registered usernames.
  """
  def list_usernames do
    usernames = SocialPomodoro.UserRegistry.list_all_usernames()

    if Enum.empty?(usernames) do
      IO.puts("No users registered yet.")
    else
      IO.puts("Registered usernames:")

      Enum.each(usernames, fn name ->
        IO.puts("  - #{name}")
      end)
    end

    usernames
  end

  ## Private

  defp do_create_room(user_id, username, status) do
    # Create the room
    {:ok, room_name} =
      SocialPomodoro.RoomRegistry.create_room(
        user_id,
        25,
        2,
        5
      )

    # Get the room PID
    {:ok, pid} = SocialPomodoro.RoomRegistry.get_room(room_name)

    # Set the desired status
    case status do
      :autostart ->
        # Room starts in autostart by default, nothing to do
        :ok

      :active ->
        # Start the session immediately
        SocialPomodoro.Room.start_session(room_name)

      :break ->
        # Start session, then fast-forward to break
        SocialPomodoro.Room.start_session(room_name)
        fast_forward_to_break(pid)
    end

    IO.puts("✓ Created test room: #{room_name}")
    IO.puts("  Username: #{username}")
    IO.puts("  User ID: #{user_id}")
    IO.puts("  Status: #{status}")
    IO.puts("  URL: http://localhost:4000/session/#{room_name}")

    {:ok, room_name}
  end

  defp fast_forward_to_break(pid) do
    # Use :sys.replace_state to skip to break state
    :sys.replace_state(pid, fn state ->
      # Cancel existing timer
      if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

      # Create a new break timer
      timer =
        SocialPomodoro.Timer.new(state.break_duration_seconds)
        |> SocialPomodoro.Timer.start()

      timer_ref = Process.send_after(pid, :tick, state.tick_interval)

      # Update state to break status
      %{
        state
        | status: :break,
          timer: timer,
          timer_ref: timer_ref,
          session_participants: Enum.map(state.participants, & &1.user_id),
          participants: Enum.map(state.participants, &%{&1 | ready_for_next: false})
      }
    end)
  end
end
