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
        # Small delay to ensure autostart timer is properly canceled
        Process.sleep(50)
        SocialPomodoro.Room.start_session(room_name)
        # Flush any pending tick messages from the autostart phase
        flush_tick_messages(pid)

      :break ->
        # Start session, then fast-forward to break
        Process.sleep(50)
        SocialPomodoro.Room.start_session(room_name)
        flush_tick_messages(pid)
        fast_forward_to_break(pid)
    end

    # Get final state to display
    final_state = SocialPomodoro.Room.get_state(pid)

    IO.puts("✓ Created test room: #{room_name}")
    IO.puts("  Username: #{username}")
    IO.puts("  User ID: #{user_id}")
    IO.puts("  Status: #{final_state.status}")
    IO.puts("  Timer: #{final_state.seconds_remaining} seconds")
    IO.puts("  URL: http://localhost:4000/room/#{room_name}")

    {:ok, room_name}
  end

  # Flush any pending :tick messages that might be in the process mailbox
  defp flush_tick_messages(pid) do
    # Give the GenServer a moment to process cancellation
    Process.sleep(10)

    # Send a synchronous call to ensure all async messages are processed
    :sys.get_state(pid)
    :ok
  end

  defp fast_forward_to_break(pid) do
    # Use :sys.replace_state to skip to break state
    new_state =
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
            participants: Enum.map(state.participants, &%{&1 | ready_for_next: false}),
            status_emoji: %{}
        }
      end)

    # Manually trigger a broadcast since we bypassed normal state transitions
    Phoenix.PubSub.broadcast(
      SocialPomodoro.PubSub,
      "rooms",
      {:room_update, serialize_for_broadcast(new_state)}
    )

    Phoenix.PubSub.broadcast(
      SocialPomodoro.PubSub,
      "room:#{new_state.name}",
      {:room_state, serialize_for_broadcast(new_state)}
    )
  end

  # Helper to serialize state for broadcast (mirrors Room.serialize_state)
  defp serialize_for_broadcast(state) do
    participants_with_usernames =
      Enum.map(state.participants, fn p ->
        username = SocialPomodoro.UserRegistry.get_username(p.user_id) || "Unknown User"
        todos = Map.get(state.todos, p.user_id, [])
        status_emoji = Map.get(state.status_emoji, p.user_id)
        chat_messages = Map.get(state.chat_messages, p.user_id, [])

        p
        |> Map.put(:username, username)
        |> Map.put(:todos, todos)
        |> Map.put(:status_emoji, status_emoji)
        |> Map.put(:chat_messages, chat_messages)
      end)

    creator_username = SocialPomodoro.UserRegistry.get_username(state.creator) || "Unknown User"

    %{
      name: state.name,
      creator: state.creator,
      creator_username: creator_username,
      duration_minutes: div(state.work_duration_seconds, 60),
      status: state.status,
      participants: participants_with_usernames,
      session_participants: state.session_participants,
      spectators_count: length(state.spectators),
      seconds_remaining: state.timer.remaining,
      break_duration_minutes: div(state.break_duration_seconds, 60),
      created_at: state.created_at,
      total_cycles: state.total_cycles,
      current_cycle: state.current_cycle,
      chat_messages: state.chat_messages
    }
  end
end
