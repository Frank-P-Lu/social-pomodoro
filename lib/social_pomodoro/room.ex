defmodule SocialPomodoro.Room do
  @moduledoc """
  GenServer managing a single pomodoro room's state and timer.
  """
  use GenServer
  require Logger

  # 1 second
  @tick_interval 1000

  defstruct [
    :room_id,
    :name,
    :creator,
    :duration_minutes,
    :status,
    :participants,
    :original_participants,
    :timer_ref,
    :seconds_remaining,
    :reactions,
    :break_duration_minutes,
    :created_at
  ]

  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(room_id))
  end

  defp via_tuple(room_id) do
    {:via, Registry, {SocialPomodoro.RoomRegistry.Registry, room_id}}
  end

  ## Client API

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  def join(room_id, user_id) do
    case SocialPomodoro.RoomRegistry.get_room(room_id) do
      {:ok, pid} -> GenServer.call(pid, {:join, user_id})
      error -> error
    end
  end

  def leave(room_id, user_id) do
    case SocialPomodoro.RoomRegistry.get_room(room_id) do
      {:ok, pid} -> GenServer.call(pid, {:leave, user_id})
      error -> error
    end
  end

  def start_session(room_id) do
    case SocialPomodoro.RoomRegistry.get_room(room_id) do
      {:ok, pid} -> GenServer.call(pid, :start_session)
      error -> error
    end
  end

  def add_reaction(room_id, user_id, emoji) do
    case SocialPomodoro.RoomRegistry.get_room(room_id) do
      {:ok, pid} -> GenServer.cast(pid, {:add_reaction, user_id, emoji})
      error -> error
    end
  end

  def go_again(room_id, user_id) do
    case SocialPomodoro.RoomRegistry.get_room(room_id) do
      {:ok, pid} -> GenServer.call(pid, {:go_again, user_id})
      error -> error
    end
  end

  ## Callbacks

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    creator = Keyword.fetch!(opts, :creator)
    duration_minutes = Keyword.fetch!(opts, :duration_minutes)

    state = %__MODULE__{
      room_id: room_id,
      name: SocialPomodoro.RoomNameGenerator.generate(),
      creator: creator,
      duration_minutes: duration_minutes,
      status: :waiting,
      participants: [%{user_id: creator, ready_for_next: false}],
      original_participants: [],
      timer_ref: nil,
      seconds_remaining: nil,
      reactions: [],
      break_duration_minutes: 5,
      created_at: System.system_time(:second)
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
  def handle_call({:join, user_id}, _from, state) do
    is_already_participant = Enum.any?(state.participants, &(&1.user_id == user_id))
    is_original_participant = Enum.member?(state.original_participants, user_id)
    is_session_in_progress = state.status in [:active, :break]

    cond do
      is_already_participant ->
        {:reply, {:error, :already_joined}, state}

      is_session_in_progress and not is_original_participant ->
        # Session in progress and user was not an original participant - can't join
        {:reply, {:error, :session_in_progress}, state}

      true ->
        # Either waiting room, or rejoining as an original participant
        new_participant = %{user_id: user_id, ready_for_next: false}
        new_state = %{state | participants: [new_participant | state.participants]}
        broadcast_room_update(new_state)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:leave, user_id}, _from, state) do
    new_participants = Enum.reject(state.participants, &(&1.user_id == user_id))

    # If room becomes empty, terminate
    if Enum.empty?(new_participants) do
      {:stop, :normal, :ok, state}
    else
      # Check if the leaving user is the creator
      new_creator =
        if state.creator == user_id do
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
    if state.status == :waiting do
      seconds = state.duration_minutes * 60
      timer_ref = Process.send_after(self(), :tick, @tick_interval)

      # Calculate wait time (time between room creation and session start)
      wait_time_seconds = System.system_time(:second) - state.created_at

      # Capture original participants (who were in the room when it started)
      original_participant_ids = Enum.map(state.participants, & &1.user_id)

      new_state = %{
        state
        | status: :active,
          seconds_remaining: seconds,
          timer_ref: timer_ref,
          reactions: [],
          original_participants: original_participant_ids
      }

      # Emit telemetry event for session start
      participant_user_ids = Enum.map(state.participants, & &1.user_id)

      :telemetry.execute(
        [:pomodoro, :session, :started],
        %{count: 1},
        %{
          room_id: state.room_id,
          participant_user_ids: participant_user_ids,
          participant_count: length(state.participants),
          wait_time_seconds: wait_time_seconds
        }
      )

      # Broadcast to all participants to navigate to session page
      Enum.each(state.participants, fn participant ->
        Phoenix.PubSub.broadcast(
          SocialPomodoro.PubSub,
          "user:#{participant.user_id}",
          {:session_started, state.room_id}
        )
      end)

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
        # Start new session
        seconds = state.duration_minutes * 60
        timer_ref = Process.send_after(self(), :tick, @tick_interval)

        final_state = %{
          new_state
          | status: :active,
            seconds_remaining: seconds,
            timer_ref: timer_ref,
            reactions: [],
            participants: Enum.map(new_participants, &%{&1 | ready_for_next: false})
        }

        # Emit telemetry event for session restart (restarted after break)
        participant_user_ids = Enum.map(new_participants, & &1.user_id)

        :telemetry.execute(
          [:pomodoro, :session, :restarted],
          %{count: 1},
          %{
            room_id: state.room_id,
            participant_user_ids: participant_user_ids,
            participant_count: length(new_participants)
          }
        )

        broadcast_room_update(final_state)
        {:reply, :ok, final_state}
      else
        broadcast_room_update(new_state)
        {:reply, :ok, new_state}
      end
    else
      {:reply, {:error, :not_in_break}, state}
    end
  end

  @impl true
  def handle_cast({:add_reaction, user_id, emoji}, state) do
    if state.status == :active do
      reaction = %{user_id: user_id, emoji: emoji, timestamp: System.system_time(:second)}
      new_state = %{state | reactions: [reaction | state.reactions]}
      broadcast_room_update(new_state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:tick, %{seconds_remaining: 0, status: :active} = state) do
    # Session complete, start break
    seconds = state.break_duration_minutes * 60
    timer_ref = Process.send_after(self(), :tick, @tick_interval)

    # Emit telemetry event for session completion
    :telemetry.execute(
      [:pomodoro, :session, :completed],
      %{count: 1},
      %{
        room_id: state.room_id,
        participant_count: length(state.participants),
        duration_minutes: state.duration_minutes
      }
    )

    new_state = %{
      state
      | status: :break,
        seconds_remaining: seconds,
        timer_ref: timer_ref,
        reactions: []
    }

    broadcast_room_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:tick, %{seconds_remaining: 0, status: :break} = state) do
    # Break complete, return to waiting
    new_state = %{state | status: :waiting, seconds_remaining: nil, timer_ref: nil, reactions: []}

    broadcast_room_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:tick, state) do
    new_seconds = state.seconds_remaining - 1
    timer_ref = Process.send_after(self(), :tick, @tick_interval)

    new_state = %{state | seconds_remaining: new_seconds, timer_ref: timer_ref}

    # Only broadcast every 5 seconds to reduce network spam
    # Still broadcast on important moments (last 10 seconds, every minute, etc)
    should_broadcast = rem(new_seconds, 5) == 0 || new_seconds <= 10

    if should_broadcast do
      broadcast_room_update(new_state)
    end

    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    # Broadcast room removal to all lobby viewers
    Phoenix.PubSub.broadcast(
      SocialPomodoro.PubSub,
      "rooms",
      {:room_removed, state.room_id}
    )

    SocialPomodoro.RoomRegistry.remove_room(state.room_id)
    :ok
  end

  ## Private Helpers

  defp broadcast_room_update(state) do
    Phoenix.PubSub.broadcast(
      SocialPomodoro.PubSub,
      "rooms",
      {:room_update, serialize_state(state)}
    )

    Phoenix.PubSub.broadcast(
      SocialPomodoro.PubSub,
      "room:#{state.room_id}",
      {:room_state, serialize_state(state)}
    )
  end

  defp serialize_state(state) do
    # Add usernames to participants for display
    participants_with_usernames =
      Enum.map(state.participants, fn p ->
        username = SocialPomodoro.UserRegistry.get_username(p.user_id) || "Unknown User"
        Map.put(p, :username, username)
      end)

    # Add usernames to reactions for display
    reactions_with_usernames =
      Enum.map(state.reactions, fn r ->
        username = SocialPomodoro.UserRegistry.get_username(r.user_id) || "Unknown User"
        Map.put(r, :username, username)
      end)

    # Get creator username
    creator_username = SocialPomodoro.UserRegistry.get_username(state.creator) || "Unknown User"

    %{
      room_id: state.room_id,
      name: state.name,
      creator: state.creator,
      creator_username: creator_username,
      duration_minutes: state.duration_minutes,
      status: state.status,
      participants: participants_with_usernames,
      original_participants: state.original_participants,
      seconds_remaining: state.seconds_remaining,
      # Latest 50 reactions
      reactions: reactions_with_usernames |> Enum.take(50) |> Enum.reverse(),
      break_duration_minutes: state.break_duration_minutes
    }
  end
end
