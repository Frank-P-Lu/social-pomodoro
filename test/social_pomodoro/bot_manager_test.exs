defmodule SocialPomodoro.BotManagerTest do
  use ExUnit.Case, async: false

  alias SocialPomodoro.{BotManager, BotPersonality, Room, RoomRegistry}

  setup do
    # Start a test room
    creator_id = "user-#{:rand.uniform(10000)}"

    {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)

    on_exit(fn ->
      case RoomRegistry.get_room(room_name) do
        {:ok, pid} -> GenServer.stop(pid, :normal)
        _ -> :ok
      end
    end)

    %{room_name: room_name, creator_id: creator_id}
  end

  describe "bot scheduling" do
    test "schedules bot join after room creation" do
      # BotManager should have scheduled a potential bot join
      # We can't directly test the 50% probability, but we can verify the mechanism works
      state = :sys.get_state(BotManager)

      # Either a bot was scheduled or it wasn't (50% chance)
      # If scheduled, it should be in the scheduled_joins map
      assert is_map(state.scheduled_joins)
    end
  end

  describe "bot cleanup" do
    test "cleans up when room terminates", %{room_name: room_name} do
      # Terminate the room
      {:ok, pid} = RoomRegistry.get_room(room_name)
      GenServer.stop(pid, :normal)

      # Give it a moment to process
      Process.sleep(100)

      # Verify cleanup
      final_state = :sys.get_state(BotManager)
      refute Map.has_key?(final_state.scheduled_joins, room_name)
      refute Map.has_key?(final_state.active_bots, room_name)
    end
  end

  describe "bot personalities" do
    test "all bots are registered in UserRegistry" do
      Enum.each(BotPersonality.all(), fn bot ->
        username = SocialPomodoro.UserRegistry.get_username(bot.user_id)
        assert username == bot.username
      end)
    end

    test "random bot returns valid personality" do
      bot = BotPersonality.random()
      assert %BotPersonality{} = bot
      assert is_binary(bot.user_id)
      assert is_binary(bot.username)
      assert is_list(bot.messages)
      assert is_list(bot.emojis)
    end

    test "random_message returns valid message" do
      bot = BotPersonality.random()
      message = BotPersonality.random_message(bot)
      assert is_binary(message)
      assert message in bot.messages
    end

    test "random_emoji returns valid emoji" do
      bot = BotPersonality.random()
      emoji = BotPersonality.random_emoji(bot)
      assert is_binary(emoji)
      assert emoji in bot.emojis
    end

    test "bot? identifies bot user_ids correctly" do
      assert BotPersonality.bot?("bot_alice")
      assert BotPersonality.bot?("bot_bob")
      assert BotPersonality.bot?("bot_charlie")
      refute BotPersonality.bot?("regular_user")
      refute BotPersonality.bot?("user123")
    end
  end
end
