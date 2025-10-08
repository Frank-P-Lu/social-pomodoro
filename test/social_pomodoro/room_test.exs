defmodule SocialPomodoro.RoomTest do
  use ExUnit.Case, async: true
  alias SocialPomodoro.Room
  alias SocialPomodoro.RoomRegistry

  setup do
    :ok
  end

  describe "room name generation" do
    test "each room gets a unique name" do
      # Create two rooms
      creator1_id = "user1_#{System.unique_integer([:positive])}"
      creator2_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room1_id} = RoomRegistry.create_room(creator1_id, 25)
      {:ok, room2_id} = RoomRegistry.create_room(creator2_id, 25)

      {:ok, room1_pid} = RoomRegistry.get_room(room1_id)
      {:ok, room2_pid} = RoomRegistry.get_room(room2_id)

      # Get the states
      room1_state = Room.get_state(room1_pid)
      room2_state = Room.get_state(room2_pid)

      # Assert both rooms have names
      assert is_binary(room1_state.name)
      assert is_binary(room2_state.name)

      # Names should follow the format: "Adjective-Noun-Noun"
      assert String.split(room1_state.name, "-") |> length() == 3
      assert String.split(room2_state.name, "-") |> length() == 3
    end
  end

  describe "creator reassignment when creator leaves" do
    test "two people in room: when creator leaves, remaining person becomes creator" do
      # Setup: Create a room with a creator
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      # Have another user join the room
      assert :ok = Room.join(room_name, participant_id)

      # Get initial state to verify setup
      initial_state = Room.get_state(room_pid)
      assert initial_state.creator == creator_id
      assert length(initial_state.participants) == 2

      # Creator leaves the room
      assert :ok = Room.leave(room_name, creator_id)

      # Get updated state
      updated_state = Room.get_state(room_pid)

      # Assert that the remaining participant is now the creator
      assert updated_state.creator == participant_id
      assert length(updated_state.participants) == 1
      assert hd(updated_state.participants).user_id == participant_id
    end

    test "multiple people in room: when creator leaves, one of remaining people becomes creator" do
      # Setup: Create a room with a creator and multiple participants
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant2_id = "user2_#{System.unique_integer([:positive])}"
      participant3_id = "user3_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      # Have other users join the room
      assert :ok = Room.join(room_name, participant2_id)
      assert :ok = Room.join(room_name, participant3_id)

      # Get initial state to verify setup
      initial_state = Room.get_state(room_pid)
      assert initial_state.creator == creator_id
      assert length(initial_state.participants) == 3

      # Creator leaves the room
      assert :ok = Room.leave(room_name, creator_id)

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
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      # Have another user join the room
      assert :ok = Room.join(room_name, participant_id)

      # Get initial state
      initial_state = Room.get_state(room_pid)
      assert initial_state.creator == creator_id
      assert length(initial_state.participants) == 2

      # Participant (non-creator) leaves the room
      assert :ok = Room.leave(room_name, participant_id)

      # Get updated state
      updated_state = Room.get_state(room_pid)

      # Assert that the creator remains the same
      assert updated_state.creator == creator_id
      assert length(updated_state.participants) == 1
      assert hd(updated_state.participants).user_id == creator_id
    end

    test "last person (creator) leaves: room terminates" do
      # Setup: Create a room with only a creator
      creator_id = "user1_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      # Verify room is alive
      assert Process.alive?(room_pid)

      # Creator leaves (last person in room)
      assert :ok = Room.leave(room_name, creator_id)

      # Give the process a moment to terminate
      Process.sleep(10)

      # Verify room process has terminated
      refute Process.alive?(room_pid)
    end
  end
end
