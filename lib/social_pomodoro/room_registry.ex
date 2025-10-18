defmodule SocialPomodoro.RoomRegistry do
  @moduledoc """
  Tracks all active rooms in memory using ETS.
  """
  use GenServer

  @table_name :room_registry

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Creates a new room and returns its name.
  """
  def create_room(creator_user_id, duration_minutes, num_cycles \\ 1, break_duration_minutes \\ 5) do
    GenServer.call(
      __MODULE__,
      {:create_room, creator_user_id, duration_minutes, num_cycles, break_duration_minutes}
    )
  end

  @doc """
  Returns a list of all rooms with their current state.
  Empty rooms are filtered out unless the user_id is an original participant.
  """
  def list_rooms(user_id) do
    GenServer.call(__MODULE__, {:list_rooms, user_id})
  end

  @doc """
  Gets a specific room by name.
  """
  def get_room(name) do
    GenServer.call(__MODULE__, {:get_room, name})
  end

  @doc """
  Finds which room (if any) a user is currently in.
  Returns {:ok, room_name} or {:error, :not_found}
  """
  def find_user_room(user_id) do
    GenServer.call(__MODULE__, {:find_user_room, user_id})
  end

  @doc """
  Removes a room from the registry (called when room process terminates).
  """
  def remove_room(name) do
    GenServer.cast(__MODULE__, {:remove_room, name})
  end

  ## Callbacks

  @impl true
  def init(:ok) do
    table = :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call(
        {:create_room, creator_user_id, duration_minutes, num_cycles, break_duration_minutes},
        _from,
        state
      ) do
    name = SocialPomodoro.RoomNameGenerator.generate()
    duration_seconds = duration_minutes * 60
    break_duration_seconds = break_duration_minutes * 60

    case SocialPomodoro.Room.start_link(
           name: name,
           creator: creator_user_id,
           duration_seconds: duration_seconds,
           break_duration_seconds: break_duration_seconds,
           total_cycles: num_cycles
         ) do
      {:ok, pid} ->
        :ets.insert(@table_name, {name, pid})

        # Emit telemetry event for room creation
        :telemetry.execute(
          [:pomodoro, :room, :created],
          %{count: 1},
          %{
            room_name: name,
            user_id: creator_user_id,
            duration_minutes: duration_minutes,
            num_cycles: num_cycles,
            break_duration_minutes: break_duration_minutes
          }
        )

        {:reply, {:ok, name}, state}

      {:error, {:already_started, _pid}} ->
        # Room name collision - retry with a new name
        handle_call(
          {:create_room, creator_user_id, duration_minutes, num_cycles, break_duration_minutes},
          self(),
          state
        )
    end
  end

  @impl true
  def handle_call({:list_rooms, user_id}, _from, state) do
    rooms =
      :ets.tab2list(@table_name)
      |> Enum.map(fn {_name, pid} ->
        if Process.alive?(pid) do
          SocialPomodoro.Room.get_state(pid)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn room ->
        # Show room if:
        # - It has participants (for discovery of waiting/active rooms)
        # - User is a session participant (so they can see rooms to rejoin)
        not Enum.empty?(room.participants) or
          Enum.member?(room.session_participants, user_id)
      end)

    {:reply, rooms, state}
  end

  @impl true
  def handle_call({:get_room, name}, _from, state) do
    case :ets.lookup(@table_name, name) do
      [{^name, pid}] when is_pid(pid) ->
        if Process.alive?(pid) do
          {:reply, {:ok, pid}, state}
        else
          :ets.delete(@table_name, name)
          {:reply, {:error, :not_found}, state}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:find_user_room, user_id}, _from, state) do
    result =
      :ets.tab2list(@table_name)
      |> Enum.find_value(fn {name, pid} ->
        if Process.alive?(pid) do
          room_state = SocialPomodoro.Room.get_raw_state(pid)

          if Enum.any?(room_state.participants, &(&1.user_id == user_id)) or
               Enum.member?(room_state.spectators, user_id) do
            name
          end
        end
      end)

    case result do
      nil -> {:reply, {:error, :not_found}, state}
      name -> {:reply, {:ok, name}, state}
    end
  end

  @impl true
  def handle_cast({:remove_room, name}, state) do
    :ets.delete(@table_name, name)
    {:noreply, state}
  end
end
