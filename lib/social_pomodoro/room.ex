defmodule SocialPomodoro.Room do
  @moduledoc """
  GenServer managing a single pomodoro room's state and timer.
  """
  use GenServer
  require Logger

  # 1 second
  @tick_interval 1000

  defstruct [
    :name,
    :creator,
    :duration_seconds,
    :status,
    :participants,
    :original_participants,
    :timer_ref,
    :seconds_remaining,
    :break_duration_seconds,
    :created_at,
    :tick_interval,
    :working_on,
    :status_emoji
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

  def set_working_on(name, user_id, text) do
    case SocialPomodoro.RoomRegistry.get_room(name) do
      {:ok, pid} -> GenServer.call(pid, {:set_working_on, user_id, text})
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

  ## Callbacks

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    creator = Keyword.fetch!(opts, :creator)
    duration_seconds = Keyword.fetch!(opts, :duration_seconds)
    tick_interval = Keyword.get(opts, :tick_interval, @tick_interval)
    break_duration_seconds = Keyword.get(opts, :break_duration_seconds, 5 * 60)

    state = %__MODULE__{
      name: name,
      creator: creator,
      duration_seconds: duration_seconds,
      status: :waiting,
      participants: [%{user_id: creator, ready_for_next: false}],
      original_participants: [],
      timer_ref: nil,
      seconds_remaining: nil,
      break_duration_seconds: break_duration_seconds,
      created_at: System.system_time(:second),
      tick_interval: tick_interval,
      working_on: %{},
      status_emoji: %{}
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

        # Track rejoin analytics if this is a rejoin during an active session
        if is_session_in_progress and is_original_participant do
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

  @impl true
  def handle_call(:start_session, _from, state) do
    if state.status == :waiting do
      seconds = state.duration_seconds
      timer_ref = Process.send_after(self(), :tick, state.tick_interval)

      # Calculate wait time (time between room creation and session start)
      wait_time_seconds = System.system_time(:second) - state.created_at

      # Capture original participants (who were in the room when it started)
      original_participant_ids = Enum.map(state.participants, & &1.user_id)

      new_state = %{
        state
        | status: :active,
          seconds_remaining: seconds,
          timer_ref: timer_ref,
          original_participants: original_participant_ids,
          working_on: %{},
          status_emoji: %{}
      }

      # Emit telemetry event for session start
      participant_user_ids = Enum.map(state.participants, & &1.user_id)

      :telemetry.execute(
        [:pomodoro, :session, :started],
        %{count: 1},
        %{
          room_name: state.name,
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
          {:session_started, state.name}
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
        # Cancel existing timer before creating new one
        if new_state.timer_ref, do: Process.cancel_timer(new_state.timer_ref)

        seconds = state.duration_seconds
        timer_ref = Process.send_after(self(), :tick, state.tick_interval)

        final_state = %{
          new_state
          | status: :active,
            seconds_remaining: seconds,
            timer_ref: timer_ref,
            participants: Enum.map(new_participants, &%{&1 | ready_for_next: false}),
            working_on: %{},
            status_emoji: %{}
        }

        # Emit telemetry event for session restart (restarted after break)
        participant_user_ids = Enum.map(new_participants, & &1.user_id)

        :telemetry.execute(
          [:pomodoro, :session, :restarted],
          %{count: 1},
          %{
            room_name: state.name,
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
  def handle_call({:set_working_on, user_id, text}, _from, state) do
    if state.status == :active do
      new_working_on = Map.put(state.working_on, user_id, text)
      new_state = %{state | working_on: new_working_on}

      # Track working_on analytics
      :telemetry.execute(
        [:pomodoro, :user, :set_working_on],
        %{count: 1},
        %{
          room_name: state.name,
          user_id: user_id,
          text_length: String.length(text)
        }
      )

      broadcast_room_update(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_active}, state}
    end
  end

  @impl true
  def handle_call({:set_status, user_id, emoji}, _from, state) do
    if state.status == :active do
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
      {:reply, {:error, :not_active}, state}
    end
  end

  @impl true
  def handle_info(:tick, %{seconds_remaining: 0, status: :active} = state) do
    # Session complete, start break
    # Cancel existing timer before creating new one
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    seconds = state.break_duration_seconds
    timer_ref = Process.send_after(self(), :tick, state.tick_interval)

    # Emit telemetry event for session completion
    :telemetry.execute(
      [:pomodoro, :session, :completed],
      %{count: 1},
      %{
        room_name: state.name,
        participant_count: length(state.participants),
        duration_minutes: div(state.duration_seconds, 60)
      }
    )

    new_state = %{
      state
      | status: :break,
        seconds_remaining: seconds,
        timer_ref: timer_ref
    }

    broadcast_room_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:tick, %{seconds_remaining: 0, status: :break} = state) do
    # Break complete, terminate the room
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:tick, state) do
    new_seconds = state.seconds_remaining - 1
    timer_ref = Process.send_after(self(), :tick, state.tick_interval)

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
      {:room_removed, state.name}
    )

    SocialPomodoro.RoomRegistry.remove_room(state.name)
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
      "room:#{state.name}",
      {:room_state, serialize_state(state)}
    )
  end

  defp serialize_state(state) do
    # Add usernames, working_on, and status_emoji to participants for display
    participants_with_usernames =
      Enum.map(state.participants, fn p ->
        username = SocialPomodoro.UserRegistry.get_username(p.user_id) || "Unknown User"
        working_on = Map.get(state.working_on, p.user_id)
        status_emoji = Map.get(state.status_emoji, p.user_id)

        p
        |> Map.put(:username, username)
        |> Map.put(:working_on, working_on)
        |> Map.put(:status_emoji, status_emoji)
      end)

    # Get creator username
    creator_username = SocialPomodoro.UserRegistry.get_username(state.creator) || "Unknown User"

    %{
      name: state.name,
      creator: state.creator,
      creator_username: creator_username,
      duration_minutes: div(state.duration_seconds, 60),
      status: state.status,
      participants: participants_with_usernames,
      original_participants: state.original_participants,
      seconds_remaining: state.seconds_remaining,
      break_duration_minutes: div(state.break_duration_seconds, 60)
    }
  end
end
