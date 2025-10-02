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
  Creates a new room and returns its ID.
  """
  def create_room(creator_username, duration_minutes) do
    GenServer.call(__MODULE__, {:create_room, creator_username, duration_minutes})
  end

  @doc """
  Returns a list of all rooms with their current state.
  """
  def list_rooms do
    GenServer.call(__MODULE__, :list_rooms)
  end

  @doc """
  Gets a specific room by ID.
  """
  def get_room(room_id) do
    GenServer.call(__MODULE__, {:get_room, room_id})
  end

  @doc """
  Removes a room from the registry (called when room process terminates).
  """
  def remove_room(room_id) do
    GenServer.cast(__MODULE__, {:remove_room, room_id})
  end

  ## Callbacks

  @impl true
  def init(:ok) do
    table = :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:create_room, creator_username, duration_minutes}, _from, state) do
    room_id = generate_room_id()

    {:ok, pid} = SocialPomodoro.Room.start_link(
      room_id: room_id,
      creator: creator_username,
      duration_minutes: duration_minutes
    )

    :ets.insert(@table_name, {room_id, pid})
    {:reply, {:ok, room_id}, state}
  end

  @impl true
  def handle_call(:list_rooms, _from, state) do
    rooms =
      :ets.tab2list(@table_name)
      |> Enum.map(fn {_room_id, pid} ->
        if Process.alive?(pid) do
          SocialPomodoro.Room.get_state(pid)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:reply, rooms, state}
  end

  @impl true
  def handle_call({:get_room, room_id}, _from, state) do
    case :ets.lookup(@table_name, room_id) do
      [{^room_id, pid}] when is_pid(pid) ->
        if Process.alive?(pid) do
          {:reply, {:ok, pid}, state}
        else
          :ets.delete(@table_name, room_id)
          {:reply, {:error, :not_found}, state}
        end
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_cast({:remove_room, room_id}, state) do
    :ets.delete(@table_name, room_id)
    {:noreply, state}
  end

  defp generate_room_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
