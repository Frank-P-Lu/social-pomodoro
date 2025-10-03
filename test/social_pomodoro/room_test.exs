defmodule SocialPomodoro.RoomTest do
  use ExUnit.Case, async: true
  alias SocialPomodoro.Room

  setup do
    # Start the necessary registries for testing
    start_supervised!({Registry, keys: :unique, name: SocialPomodoro.RoomRegistry.Registry})
    start_supervised!(SocialPomodoro.UserRegistry)
    start_supervised!({Phoenix.PubSub, name: SocialPomodoro.PubSub})

    :ok
  end

  describe "creator reassignment when creator leaves" do
    test "two people in room: when creator leaves, remaining person becomes creator" do
      # Setup: Create a room with a creator
      creator_id = "user1"
      participant_id = "user2"
      room_id = "test_room_#{System.unique_integer([:positive])}"

      {:ok, room_pid} =
        Room.start_link(
          room_id: room_id,
          creator: creator_id,
          duration_minutes: 25
        )

      # Have another user join the room
      assert :ok = Room.join(room_id, participant_id)

      # Get initial state to verify setup
      initial_state = Room.get_state(room_pid)
      assert initial_state.creator == creator_id
      assert length(initial_state.participants) == 2

      # Creator leaves the room
      assert :ok = Room.leave(room_id, creator_id)

      # Get updated state
      updated_state = Room.get_state(room_pid)

      # Assert that the remaining participant is now the creator
      assert updated_state.creator == participant_id
      assert length(updated_state.participants) == 1
      assert hd(updated_state.participants).user_id == participant_id
    end

    test "multiple people in room: when creator leaves, one of remaining people becomes creator" do
      # Setup: Create a room with a creator and multiple participants
      creator_id = "user1"
      participant2_id = "user2"
      participant3_id = "user3"
      room_id = "test_room_#{System.unique_integer([:positive])}"

      {:ok, room_pid} =
        Room.start_link(
          room_id: room_id,
          creator: creator_id,
          duration_minutes: 25
        )

      # Have other users join the room
      assert :ok = Room.join(room_id, participant2_id)
      assert :ok = Room.join(room_id, participant3_id)

      # Get initial state to verify setup
      initial_state = Room.get_state(room_pid)
      assert initial_state.creator == creator_id
      assert length(initial_state.participants) == 3

      # Creator leaves the room
      assert :ok = Room.leave(room_id, creator_id)

      # Get updated state
      updated_state = Room.get_state(room_pid)

      # Assert that one of the remaining participants is now the creator
      assert updated_state.creator != creator_id
      assert updated_state.creator in [participant2_id, participant3_id]
      assert length(updated_state.participants) == 2

      # Verify the new creator is one of the remaining participants
      remaining_user_ids = Enum.map(updated_state.participants, & &1.user_id)
      assert updated_state.creator in remaining_user_ids
    end

    test "non-creator leaves: creator remains the same" do
      # Setup: Create a room with a creator and a participant
      creator_id = "user1"
      participant_id = "user2"
      room_id = "test_room_#{System.unique_integer([:positive])}"

      {:ok, room_pid} =
        Room.start_link(
          room_id: room_id,
          creator: creator_id,
          duration_minutes: 25
        )

      # Have another user join the room
      assert :ok = Room.join(room_id, participant_id)

      # Get initial state
      initial_state = Room.get_state(room_pid)
      assert initial_state.creator == creator_id
      assert length(initial_state.participants) == 2

      # Participant (non-creator) leaves the room
      assert :ok = Room.leave(room_id, participant_id)

      # Get updated state
      updated_state = Room.get_state(room_pid)

      # Assert that the creator remains the same
      assert updated_state.creator == creator_id
      assert length(updated_state.participants) == 1
      assert hd(updated_state.participants).user_id == creator_id
    end

    test "last person (creator) leaves: room terminates" do
      # Setup: Create a room with only a creator
      creator_id = "user1"
      room_id = "test_room_#{System.unique_integer([:positive])}"

      {:ok, room_pid} =
        Room.start_link(
          room_id: room_id,
          creator: creator_id,
          duration_minutes: 25
        )

      # Verify room is alive
      assert Process.alive?(room_pid)

      # Creator leaves (last person in room)
      assert :ok = Room.leave(room_id, creator_id)

      # Give the process a moment to terminate
      Process.sleep(10)

      # Verify room process has terminated
      refute Process.alive?(room_pid)
    end
  end
end
