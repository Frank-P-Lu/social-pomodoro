defmodule SocialPomodoro.UserRegistry do
  @moduledoc """
  Maps user_id → username in memory.
  Allows usernames to be updated while keeping persistent user identity.
  """
  use GenServer

  @table_name :user_registry

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Gets username for a user_id. Returns nil if not found.
  """
  def get_username(user_id) do
    case :ets.lookup(@table_name, user_id) do
      [{^user_id, username}] -> username
      [] -> nil
    end
  end

  @doc """
  Sets username for a user_id.
  """
  def set_username(user_id, username) do
    GenServer.call(__MODULE__, {:set_username, user_id, username})
  end

  @doc """
  Removes a user from the registry.
  """
  def remove_user(user_id) do
    GenServer.cast(__MODULE__, {:remove_user, user_id})
  end

  ## Callbacks

  @impl true
  def init(:ok) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:set_username, user_id, username}, _from, state) do
    :ets.insert(@table_name, {user_id, username})

    # Broadcast username change
    Phoenix.PubSub.broadcast(
      SocialPomodoro.PubSub,
      "user:#{user_id}",
      {:username_updated, user_id, username}
    )

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:remove_user, user_id}, state) do
    :ets.delete(@table_name, user_id)
    {:noreply, state}
  end
end
