defmodule SocialPomodoro.Room do
  @moduledoc """
  GenServer managing a single pomodoro room's state and timer.
  """
  use GenServer
  require Logger

  alias SocialPomodoro.Timer

  # 1 second
  @tick_interval 1000

  @type status :: :autostart | :active | :break

  defstruct [
    :name,
    :creator,
    :status,
    :participants,
    :session_participants,
    :spectators,
    :timer_ref,
    :timer,
    :work_duration_seconds,
    :break_duration_seconds,
    :created_at,
    :tick_interval,
    :todos,
    :status_emoji,
    :total_cycles,
    :current_cycle,
    :chat_messages
  ]

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  defp via_tuple(name) do
    {:via, Registry, {SocialPomodoro.RoomRegistry.Registry, name}}
  end

  ## Client API

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  def get_raw_state(pid) do
    GenServer.call(pid, :get_raw_state)
  end

  def join(name, user_id) do
    case SocialPomodoro.RoomRegistry.get_room(name) do
      {:ok, pid} -> GenServer.call(pid, {:join, user_id})
      error -> error
    end
  end

  def leave(name, user_id) do
    case SocialPomodoro.RoomRegistry.get_room(name) do
      {:ok, pid} -> GenServer.call(pid, {:leave, user_id})
      error -> error
    end
  end

  def start_session(name) do
    case SocialPomodoro.RoomRegistry.get_room(name) do
      {:ok, pid} -> GenServer.call(pid, :start_session)
      error -> error
    end
  end

  def add_todo(name, user_id, text) do
    case SocialPomodoro.RoomRegistry.get_room(name) do
      {:ok, pid} -> GenServer.call(pid, {:add_todo, user_id, text})
      error -> error
    end
  end

  def toggle_todo(name, user_id, todo_id) do
    case SocialPomodoro.RoomRegistry.get_room(name) do
      {:ok, pid} -> GenServer.call(pid, {:toggle_todo, user_id, todo_id})
      error -> error
    end
  end

  def delete_todo(name, user_id, todo_id) do
    case SocialPomodoro.RoomRegistry.get_room(name) do
      {:ok, pid} -> GenServer.call(pid, {:delete_todo, user_id, todo_id})
      error -> error
    end
  end

  def set_status(name, user_id, emoji) do
    case SocialPomodoro.RoomRegistry.get_room(name) do
      {:ok, pid} -> GenServer.call(pid, {:set_status, user_id, emoji})
      error -> error
    end
  end

  def go_again(name, user_id) do
    case SocialPomodoro.RoomRegistry.get_room(name) do
      {:ok, pid} -> GenServer.call(pid, {:go_again, user_id})
      error -> error
    end
  end

  def send_chat_message(name, user_id, text) do
    case SocialPomodoro.RoomRegistry.get_room(name) do
      {:ok, pid} -> GenServer.call(pid, {:send_chat_message, user_id, text})
      error -> error
    end
  end

  ## Callbacks

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    creator = Keyword.fetch!(opts, :creator)
    duration_seconds = Keyword.fetch!(opts, :duration_seconds)
    tick_interval = Keyword.get(opts, :tick_interval, @tick_interval)
    break_duration_seconds = Keyword.get(opts, :break_duration_seconds, 5 * 60)
    total_cycles = Keyword.get(opts, :total_cycles, 1)

    # Start autostart countdown (configurable in SocialPomodoro.Config)
    autostart_seconds = SocialPomodoro.Config.autostart_countdown_seconds()
    timer_ref = Process.send_after(self(), :tick, tick_interval)
    timer = Timer.new(autostart_seconds) |> Timer.start()

    state = %__MODULE__{
      name: name,
      creator: creator,
      work_duration_seconds: duration_seconds,
      status: :autostart,
      participants: [%{user_id: creator, ready_for_next: false}],
      session_participants: [],
      spectators: [],
      timer_ref: timer_ref,
      timer: timer,
      break_duration_seconds: break_duration_seconds,
      created_at: System.system_time(:second),
      tick_interval: tick_interval,
      todos: %{},
      status_emoji: %{},
      total_cycles: total_cycles,
      current_cycle: 1,
      chat_messages: %{}
    }

    {:ok, state, {:continue, :broadcast_update}}
  end

  @impl true
  def handle_continue(:broadcast_update, state) do
    broadcast_room_update(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, serialize_state(state), state}
  end

  @impl true
  def handle_call(:get_raw_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:join, user_id}, _from, state) do
    is_already_participant = Enum.any?(state.participants, &(&1.user_id == user_id))
    is_already_spectator = Enum.member?(state.spectators, user_id)
    is_session_participant = Enum.member?(state.session_participants, user_id)

    cond do
      is_already_participant ->
        {:reply, {:error, :already_joined}, state}

      is_already_spectator ->
        {:reply, {:error, :already_spectator}, state}

      state.status == :active and not is_session_participant ->
        # Session in progress and user was not a session participant - join as spectator
        new_state = %{state | spectators: [user_id | state.spectators]}

        :telemetry.execute(
          [:pomodoro, :spectator, :joined],
          %{count: 1},
          %{
            room_name: state.name,
            user_id: user_id
          }
        )

        broadcast_room_update(new_state)
        {:reply, :ok, new_state}

      true ->
        # Either autostart, break, or rejoining as a session participant
        new_participant = %{user_id: user_id, ready_for_next: false}
        new_state = %{state | participants: [new_participant | state.participants]}

        # Track rejoin analytics if this is a rejoin during an active session
        if state.status in [:active, :break] and is_session_participant do
          :telemetry.execute(
            [:pomodoro, :user, :rejoined],
            %{count: 1},
            %{
              room_name: state.name,
              user_id: user_id,
              room_status: state.status
            }
          )
        end

        broadcast_room_update(new_state)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:leave, user_id}, _from, state) do
    was_spectator = Enum.member?(state.spectators, user_id)

    if was_spectator do
      # Remove from spectators
      new_spectators = List.delete(state.spectators, user_id)
      new_state = %{state | spectators: new_spectators}

      :telemetry.execute(
        [:pomodoro, :spectator, :left],
        %{count: 1},
        %{
          room_name: state.name,
          user_id: user_id
        }
      )

      broadcast_room_update(new_state)
      {:reply, :ok, new_state}
    else
      # Remove from participants
      new_participants = Enum.reject(state.participants, &(&1.user_id == user_id))

      # Check if the leaving user is the creator
      new_creator =
        if state.creator == user_id && not Enum.empty?(new_participants) do
          # Assign a random remaining participant as the new creator
          random_participant = Enum.random(new_participants)
          random_participant.user_id
        else
          state.creator
        end

      new_state = %{state | participants: new_participants, creator: new_creator}
      broadcast_room_update(new_state)
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:start_session, _from, state) do
    if state.status == :autostart do
      new_state = do_start_session(state, manual_start: true)
      broadcast_room_update(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :already_started}, state}
    end
  end

  @impl true
  def handle_call({:go_again, user_id}, _from, state) do
    if state.status == :break do
      # Mark this user as ready for next round
      new_participants =
        Enum.map(state.participants, fn p ->
          if p.user_id == user_id do
            %{p | ready_for_next: true}
          else
            p
          end
        end)

      # Check if all participants are ready
      all_ready = Enum.all?(new_participants, & &1.ready_for_next)

      new_state = %{state | participants: new_participants}

      if all_ready do
        # All participants ready to skip break
        if new_state.timer_ref, do: Process.cancel_timer(new_state.timer_ref)

        # Check if more cycles remain
        if state.current_cycle < state.total_cycles do
          # Start next cycle immediately
          timer = Timer.new(state.work_duration_seconds) |> Timer.start()
          timer_ref = Process.send_after(self(), :tick, state.tick_interval)

          final_state = %{
            new_state
            | status: :active,
              timer: timer,
              timer_ref: timer_ref,
              current_cycle: state.current_cycle + 1,
              participants: Enum.map(new_participants, &%{&1 | ready_for_next: false}),
              status_emoji: %{},
              chat_messages: %{}
          }

          # Emit telemetry event for break skip
          :telemetry.execute(
            [:pomodoro, :break, :skipped],
            %{count: 1},
            %{
              room_name: state.name,
              cycle: final_state.current_cycle,
              total_cycles: state.total_cycles,
              participant_count: length(new_participants)
            }
          )

          broadcast_room_update(final_state)
          {:reply, :ok, final_state}
        else
          # This was the final break - button should be hidden in UI
          {:reply, {:error, :final_break}, new_state}
        end
      else
        broadcast_room_update(new_state)
        {:reply, :ok, new_state}
      end
    else
      {:reply, {:error, :not_in_break}, state}
    end
  end

  @impl true
  def handle_call({:add_todo, user_id, text}, _from, state) do
    if state.status in [:active, :break] do
      user_todos = Map.get(state.todos, user_id, [])
      max_todos = SocialPomodoro.Config.max_todos_per_user()

      if length(user_todos) >= max_todos do
        {:reply, {:error, :max_todos_reached}, state}
      else
        new_todo = %{
          id: generate_todo_id(),
          text: text,
          completed: false
        }

        new_user_todos = user_todos ++ [new_todo]
        new_todos = Map.put(state.todos, user_id, new_user_todos)
        new_state = %{state | todos: new_todos}

        # Track analytics
        :telemetry.execute(
          [:pomodoro, :user, :add_todo],
          %{count: 1},
          %{
            room_name: state.name,
            user_id: user_id,
            text_length: String.length(text),
            status: state.status
          }
        )

        broadcast_room_update(new_state)
        {:reply, :ok, new_state}
      end
    else
      {:reply, {:error, :invalid_status}, state}
    end
  end

  @impl true
  def handle_call({:toggle_todo, user_id, todo_id}, _from, state) do
    if state.status in [:active, :break] do
      user_todos = Map.get(state.todos, user_id, [])

      case Enum.find_index(user_todos, &(&1.id == todo_id)) do
        nil ->
          {:reply, {:error, :todo_not_found}, state}

        index ->
          todo = Enum.at(user_todos, index)
          updated_todo = %{todo | completed: !todo.completed}
          updated_user_todos = List.replace_at(user_todos, index, updated_todo)
          new_todos = Map.put(state.todos, user_id, updated_user_todos)
          new_state = %{state | todos: new_todos}

          broadcast_room_update(new_state)
          {:reply, :ok, new_state}
      end
    else
      {:reply, {:error, :invalid_status}, state}
    end
  end

  @impl true
  def handle_call({:delete_todo, user_id, todo_id}, _from, state) do
    if state.status in [:active, :break] do
      user_todos = Map.get(state.todos, user_id, [])
      new_user_todos = Enum.reject(user_todos, &(&1.id == todo_id))

      if length(new_user_todos) == length(user_todos) do
        {:reply, {:error, :todo_not_found}, state}
      else
        new_todos = Map.put(state.todos, user_id, new_user_todos)
        new_state = %{state | todos: new_todos}

        broadcast_room_update(new_state)
        {:reply, :ok, new_state}
      end
    else
      {:reply, {:error, :invalid_status}, state}
    end
  end

  @impl true
  def handle_call({:set_status, user_id, emoji}, _from, state) do
    if state.status in [:active, :break] do
      # Toggle: if same emoji, remove from map; otherwise set to new emoji
      new_status_emoji =
        if state.status_emoji[user_id] == emoji do
          Map.delete(state.status_emoji, user_id)
        else
          Map.put(state.status_emoji, user_id, emoji)
        end

      new_state = %{state | status_emoji: new_status_emoji}
      broadcast_room_update(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :invalid_status}, state}
    end
  end

  @impl true
  def handle_call({:send_chat_message, user_id, text}, _from, state) do
    if state.status == :break do
      # Validate message length (max 50 chars)
      if String.length(text) > 50 do
        {:reply, {:error, :message_too_long}, state}
      else
        # Get existing messages for this user
        user_messages = Map.get(state.chat_messages, user_id, [])

        # Add new message and maintain max 3 messages (FIFO)
        new_user_messages =
          (user_messages ++ [%{text: text, timestamp: System.system_time(:second)}])
          |> Enum.take(-3)

        new_chat_messages = Map.put(state.chat_messages, user_id, new_user_messages)
        new_state = %{state | chat_messages: new_chat_messages}

        broadcast_room_update(new_state)
        {:reply, :ok, new_state}
      end
    else
      {:reply, {:error, :not_in_break}, state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    case Timer.tick(state.timer) do
      {:ok, updated_timer} ->
        # Timer still running
        timer_ref = Process.send_after(self(), :tick, state.tick_interval)
        new_state = %{state | timer: updated_timer, timer_ref: timer_ref}

        # Broadcast strategy depends on status:
        # - autostart: only broadcast every 10 seconds (client handles countdown independently)
        # - active/break: broadcast every 10 seconds or in final 10 seconds
        should_broadcast =
          case state.status do
            :autostart ->
              # During autostart, broadcast every 10 seconds for sync only
              rem(updated_timer.remaining, 10) == 0

            _ ->
              # During session/break, broadcast every 10 seconds or in final 10 seconds
              rem(updated_timer.remaining, 10) == 0 || updated_timer.remaining <= 10
          end

        if should_broadcast do
          broadcast_room_update(new_state)
        end

        {:noreply, new_state}

      {:done, _timer} ->
        # Timer completed, handle transition
        handle_timer_complete(state)
    end
  end

  defp handle_timer_complete(%{status: :autostart} = state) do
    # Autostart countdown complete
    if Enum.empty?(state.participants) do
      # No participants, terminate the room
      {:stop, :normal, state}
    else
      # Has participants, auto-start the session
      new_state = do_start_session(state, autostart: true)
      broadcast_room_update(new_state)
      {:noreply, new_state}
    end
  end

  defp handle_timer_complete(%{status: :active} = state) do
    # Session complete, start break
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    timer = Timer.new(state.break_duration_seconds) |> Timer.start()
    timer_ref = Process.send_after(self(), :tick, state.tick_interval)

    # Emit telemetry event for session completion
    :telemetry.execute(
      [:pomodoro, :session, :completed],
      %{count: 1},
      %{
        room_name: state.name,
        participant_count: length(state.participants),
        duration_minutes: div(state.work_duration_seconds, 60)
      }
    )

    # Promote spectators to participants during break
    promoted_participants =
      Enum.map(state.spectators, fn user_id ->
        %{user_id: user_id, ready_for_next: false}
      end)

    # Emit telemetry for each spectator promotion
    Enum.each(state.spectators, fn user_id ->
      :telemetry.execute(
        [:pomodoro, :spectator, :promoted],
        %{count: 1},
        %{
          room_name: state.name,
          user_id: user_id,
          spectator_count: length(state.spectators)
        }
      )
    end)

    new_state = %{
      state
      | status: :break,
        timer: timer,
        timer_ref: timer_ref,
        participants: state.participants ++ promoted_participants,
        spectators: [],
        status_emoji: %{}
    }

    broadcast_room_update(new_state)
    {:noreply, new_state}
  end

  defp handle_timer_complete(%{status: :break} = state) do
    # Break complete - check if more cycles remain
    if state.current_cycle < state.total_cycles do
      # More cycles to go - start next work session
      if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

      timer = Timer.new(state.work_duration_seconds) |> Timer.start()
      timer_ref = Process.send_after(self(), :tick, state.tick_interval)

      new_state = %{
        state
        | status: :active,
          timer: timer,
          timer_ref: timer_ref,
          current_cycle: state.current_cycle + 1,
          participants: Enum.map(state.participants, &%{&1 | ready_for_next: false}),
          status_emoji: %{},
          chat_messages: %{}
      }

      # Emit telemetry event for next cycle start
      :telemetry.execute(
        [:pomodoro, :cycle, :started],
        %{count: 1},
        %{
          room_name: state.name,
          cycle: new_state.current_cycle,
          total_cycles: state.total_cycles,
          participant_count: length(new_state.participants)
        }
      )

      broadcast_room_update(new_state)
      {:noreply, new_state}
    else
      # All cycles complete - terminate the room
      {:stop, :normal, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Broadcast room removal to all lobby viewers
    Phoenix.PubSub.broadcast(
      SocialPomodoro.PubSub,
      "rooms",
      {:room_removed, state.name}
    )

    SocialPomodoro.RoomRegistry.remove_room(state.name)
    :ok
  end

  ## Private Helpers

  defp generate_todo_id do
    # Generate a random UUID-like string
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp do_start_session(state, opts) do
    # Cancel existing timer before creating new one
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    timer = Timer.new(state.work_duration_seconds) |> Timer.start()
    timer_ref = Process.send_after(self(), :tick, state.tick_interval)

    # Calculate wait time (time between room creation and session start)
    wait_time_seconds = System.system_time(:second) - state.created_at

    # Capture session participants (who were in the room when it started)
    session_participant_ids = Enum.map(state.participants, & &1.user_id)

    new_state = %{
      state
      | status: :active,
        timer: timer,
        timer_ref: timer_ref,
        session_participants: session_participant_ids,
        status_emoji: %{}
    }

    # Emit telemetry event for session start
    participant_user_ids = Enum.map(state.participants, & &1.user_id)

    telemetry_metadata = %{
      room_name: state.name,
      participant_user_ids: participant_user_ids,
      participant_count: length(state.participants),
      wait_time_seconds: wait_time_seconds
    }

    # Add optional metadata
    telemetry_metadata =
      Enum.reduce(opts, telemetry_metadata, fn {key, value}, acc ->
        Map.put(acc, key, value)
      end)

    :telemetry.execute(
      [:pomodoro, :session, :started],
      %{count: 1},
      telemetry_metadata
    )

    # Broadcast to all participants to navigate to session page
    Enum.each(state.participants, fn participant ->
      Phoenix.PubSub.broadcast(
        SocialPomodoro.PubSub,
        "user:#{participant.user_id}",
        {:session_started, state.name}
      )
    end)

    new_state
  end

  # TODO: optimise when this is called
  defp broadcast_room_update(state) do
    Phoenix.PubSub.broadcast(
      SocialPomodoro.PubSub,
      "rooms",
      {:room_update, serialize_state(state)}
    )

    Phoenix.PubSub.broadcast(
      SocialPomodoro.PubSub,
      "room:#{state.name}",
      {:room_state, serialize_state(state)}
    )
  end

  defp serialize_state(state) do
    # Add usernames, todos, status_emoji, and chat_messages to participants for display
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

    # Get creator username
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
      current_cycle: state.current_cycle
    }
  end
end
