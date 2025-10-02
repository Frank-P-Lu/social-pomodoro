defmodule SocialPomodoro.Room do
  @moduledoc """
  GenServer managing a single pomodoro room's state and timer.
  """
  use GenServer
  require Logger

  @tick_interval 1000  # 1 second

  defstruct [
    :room_id,
    :creator,
    :duration_minutes,
    :status,
    :participants,
    :timer_ref,
    :seconds_remaining,
    :reactions,
    :break_duration_minutes
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

  def join(room_id, username) do
    case SocialPomodoro.RoomRegistry.get_room(room_id) do
      {:ok, pid} -> GenServer.call(pid, {:join, username})
      error -> error
    end
  end

  def leave(room_id, username) do
    case SocialPomodoro.RoomRegistry.get_room(room_id) do
      {:ok, pid} -> GenServer.call(pid, {:leave, username})
      error -> error
    end
  end

  def start_session(room_id) do
    case SocialPomodoro.RoomRegistry.get_room(room_id) do
      {:ok, pid} -> GenServer.call(pid, :start_session)
      error -> error
    end
  end

  def add_reaction(room_id, username, emoji) do
    case SocialPomodoro.RoomRegistry.get_room(room_id) do
      {:ok, pid} -> GenServer.cast(pid, {:add_reaction, username, emoji})
      error -> error
    end
  end

  def go_again(room_id, username) do
    case SocialPomodoro.RoomRegistry.get_room(room_id) do
      {:ok, pid} -> GenServer.call(pid, {:go_again, username})
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
      creator: creator,
      duration_minutes: duration_minutes,
      status: :waiting,
      participants: [%{username: creator, ready_for_next: false}],
      timer_ref: nil,
      seconds_remaining: nil,
      reactions: [],
      break_duration_minutes: 5
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
  def handle_call({:join, username}, _from, state) do
    cond do
      state.status != :waiting ->
        {:reply, {:error, :session_in_progress}, state}

      Enum.any?(state.participants, &(&1.username == username)) ->
        {:reply, {:error, :already_joined}, state}

      true ->
        new_participant = %{username: username, ready_for_next: false}
        new_state = %{state | participants: [new_participant | state.participants]}
        broadcast_room_update(new_state)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:leave, username}, _from, state) do
    new_participants = Enum.reject(state.participants, &(&1.username == username))

    # If room becomes empty, terminate
    if Enum.empty?(new_participants) do
      {:stop, :normal, :ok, state}
    else
      new_state = %{state | participants: new_participants}
      broadcast_room_update(new_state)
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:start_session, _from, state) do
    if state.status == :waiting do
      seconds = state.duration_minutes * 60
      timer_ref = Process.send_after(self(), :tick, @tick_interval)

      new_state = %{state |
        status: :active,
        seconds_remaining: seconds,
        timer_ref: timer_ref,
        reactions: []
      }

      broadcast_room_update(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :already_started}, state}
    end
  end

  @impl true
  def handle_call({:go_again, username}, _from, state) do
    if state.status == :break do
      # Mark this user as ready for next round
      new_participants = Enum.map(state.participants, fn p ->
        if p.username == username do
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

        final_state = %{new_state |
          status: :active,
          seconds_remaining: seconds,
          timer_ref: timer_ref,
          reactions: [],
          participants: Enum.map(new_participants, &%{&1 | ready_for_next: false})
        }

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
  def handle_cast({:add_reaction, username, emoji}, state) do
    if state.status == :active do
      reaction = %{username: username, emoji: emoji, timestamp: System.system_time(:second)}
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

    new_state = %{state |
      status: :break,
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
    new_state = %{state |
      status: :waiting,
      seconds_remaining: nil,
      timer_ref: nil,
      reactions: []
    }

    broadcast_room_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:tick, state) do
    new_seconds = state.seconds_remaining - 1
    timer_ref = Process.send_after(self(), :tick, @tick_interval)

    new_state = %{state |
      seconds_remaining: new_seconds,
      timer_ref: timer_ref
    }

    broadcast_room_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
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
    %{
      room_id: state.room_id,
      creator: state.creator,
      duration_minutes: state.duration_minutes,
      status: state.status,
      participants: state.participants,
      seconds_remaining: state.seconds_remaining,
      reactions: state.reactions |> Enum.take(50) |> Enum.reverse(),  # Latest 50 reactions
      break_duration_minutes: state.break_duration_minutes
    }
  end
end
