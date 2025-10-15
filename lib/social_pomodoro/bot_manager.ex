defmodule SocialPomodoro.BotManager do
  @moduledoc """
  Manages bot participation in pomodoro rooms.
  
  Bots have a 50% chance of joining a room 15 seconds after creation.
  During breaks, bots stay for exactly 1 minute, send a message, and react with an emoji.
  """
  use GenServer
  require Logger

  alias SocialPomodoro.BotPersonality
  alias SocialPomodoro.Room

  # 15 seconds after room creation
  @join_delay_ms 15_000
  # 50% chance of joining
  @join_probability 0.5
  # Bot stays for 1 minute during break
  @bot_break_duration_ms 60_000

  defstruct [
    :scheduled_joins,
    :active_bots
  ]

  @type bot_state :: %{
          room_name: String.t(),
          personality: BotPersonality.t(),
          joined_at: integer(),
          message_sent?: boolean(),
          emoji_sent?: boolean()
        }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  ## Client API

  @doc """
  Schedules a potential bot join for a newly created room.
  """
  def schedule_bot_join(room_name) do
    GenServer.cast(__MODULE__, {:schedule_bot_join, room_name})
  end

  @doc """
  Notifies the bot manager that a room has terminated.
  Cleans up any scheduled or active bots for that room.
  """
  def room_terminated(room_name) do
    GenServer.cast(__MODULE__, {:room_terminated, room_name})
  end

  ## Callbacks

  @impl true
  def init(:ok) do
    # Register all bot usernames in the UserRegistry
    Enum.each(BotPersonality.all(), fn bot ->
      SocialPomodoro.UserRegistry.set_username(bot.user_id, bot.username)
    end)

    state = %__MODULE__{
      scheduled_joins: %{},
      active_bots: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:schedule_bot_join, room_name}, state) do
    # 50% chance of scheduling a bot
    if :rand.uniform() <= @join_probability do
      # Schedule bot join after delay
      timer_ref = Process.send_after(self(), {:execute_bot_join, room_name}, @join_delay_ms)

      new_scheduled_joins = Map.put(state.scheduled_joins, room_name, timer_ref)
      {:noreply, %{state | scheduled_joins: new_scheduled_joins}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:room_terminated, room_name}, state) do
    # Cancel any scheduled joins
    new_scheduled_joins =
      case Map.pop(state.scheduled_joins, room_name) do
        {nil, remaining} ->
          remaining

        {timer_ref, remaining} ->
          Process.cancel_timer(timer_ref)
          remaining
      end

    # Remove any active bots
    new_active_bots = Map.delete(state.active_bots, room_name)

    {:noreply, %{state | scheduled_joins: new_scheduled_joins, active_bots: new_active_bots}}
  end

  @impl true
  def handle_info({:execute_bot_join, room_name}, state) do
    # Remove from scheduled joins
    new_scheduled_joins = Map.delete(state.scheduled_joins, room_name)

    # Try to join the room
    case SocialPomodoro.RoomRegistry.get_room(room_name) do
      {:ok, _pid} ->
        personality = BotPersonality.random()

        case Room.join(room_name, personality.user_id) do
          :ok ->
            Logger.info("Bot #{personality.username} joined room #{room_name}")

            # Subscribe to room events to know when break starts
            Phoenix.PubSub.subscribe(SocialPomodoro.PubSub, "room:#{room_name}")

            bot_state = %{
              room_name: room_name,
              personality: personality,
              joined_at: System.system_time(:second),
              message_sent?: false,
              emoji_sent?: false
            }

            new_active_bots = Map.put(state.active_bots, room_name, bot_state)

            {:noreply,
             %{state | scheduled_joins: new_scheduled_joins, active_bots: new_active_bots}}

          {:error, reason} ->
            Logger.warning(
              "Bot #{personality.username} failed to join room #{room_name}: #{inspect(reason)}"
            )

            {:noreply, %{state | scheduled_joins: new_scheduled_joins}}
        end

      {:error, :not_found} ->
        Logger.debug("Room #{room_name} not found, bot join cancelled")
        {:noreply, %{state | scheduled_joins: new_scheduled_joins}}
    end
  end

  @impl true
  def handle_info({:room_state, room_state}, state) do
    # Check if this room has an active bot and if break just started
    case Map.get(state.active_bots, room_state.name) do
      nil ->
        {:noreply, state}

      bot_state ->
        if room_state.status == :break and not bot_state.message_sent? do
          # Break just started, schedule bot actions
          schedule_bot_break_actions(bot_state)
          {:noreply, state}
        else
          {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info({:send_bot_message, room_name}, state) do
    case Map.get(state.active_bots, room_name) do
      nil ->
        {:noreply, state}

      bot_state ->
        personality = bot_state.personality
        message = BotPersonality.random_message(personality)

        Room.set_status_message(room_name, personality.user_id, message)
        Logger.debug("Bot #{personality.username} sent message in #{room_name}: #{message}")

        updated_bot_state = %{bot_state | message_sent?: true}
        new_active_bots = Map.put(state.active_bots, room_name, updated_bot_state)

        {:noreply, %{state | active_bots: new_active_bots}}
    end
  end

  @impl true
  def handle_info({:send_bot_emoji, room_name}, state) do
    case Map.get(state.active_bots, room_name) do
      nil ->
        {:noreply, state}

      bot_state ->
        personality = bot_state.personality
        emoji = BotPersonality.random_emoji(personality)

        Room.set_status(room_name, personality.user_id, emoji)
        Logger.debug("Bot #{personality.username} sent emoji in #{room_name}: #{emoji}")

        updated_bot_state = %{bot_state | emoji_sent?: true}
        new_active_bots = Map.put(state.active_bots, room_name, updated_bot_state)

        {:noreply, %{state | active_bots: new_active_bots}}
    end
  end

  @impl true
  def handle_info({:bot_leave, room_name}, state) do
    case Map.get(state.active_bots, room_name) do
      nil ->
        {:noreply, state}

      bot_state ->
        personality = bot_state.personality

        Room.leave(room_name, personality.user_id)
        Logger.info("Bot #{personality.username} left room #{room_name}")

        new_active_bots = Map.delete(state.active_bots, room_name)

        {:noreply, %{state | active_bots: new_active_bots}}
    end
  end

  @impl true
  def handle_info({:room_removed, _room_name}, state) do
    # Room was removed, ignore (cleanup handled by room_terminated)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    # Ignore other PubSub messages
    {:noreply, state}
  end

  ## Private Helpers

  defp schedule_bot_break_actions(bot_state) do
    room_name = bot_state.room_name

    # Send message after random delay (5-15 seconds)
    message_delay = :rand.uniform(10_000) + 5_000
    Process.send_after(self(), {:send_bot_message, room_name}, message_delay)

    # Send emoji after message (2-5 seconds after message)
    emoji_delay = message_delay + :rand.uniform(3_000) + 2_000
    Process.send_after(self(), {:send_bot_emoji, room_name}, emoji_delay)

    # Leave after 1 minute total
    Process.send_after(self(), {:bot_leave, room_name}, @bot_break_duration_ms)
  end
end
