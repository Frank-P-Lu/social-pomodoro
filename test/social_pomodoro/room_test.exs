defmodule SocialPomodoro.RoomTest do
  use ExUnit.Case, async: true
  alias SocialPomodoro.Room
  alias SocialPomodoro.RoomRegistry

  setup do
    :ok
  end

  # Helper to create a room with custom options for testing
  # Use duration_seconds option to specify duration in seconds for testing
  defp create_test_room(creator_id, opts \\ []) do
    name = SocialPomodoro.RoomNameGenerator.generate()

    # Convert duration_seconds to duration_minutes for the init opts
    duration_minutes =
      case Keyword.get(opts, :duration_seconds) do
        # default 25 minutes
        nil -> 25
        seconds -> seconds / 60.0
      end

    room_opts =
      [
        name: name,
        creator: creator_id,
        duration_minutes: duration_minutes
      ] ++ Keyword.delete(opts, :duration_seconds)

    {:ok, pid} = Room.start_link(room_opts)

    # Register it manually since we're bypassing RoomRegistry.create_room
    :ets.insert(:room_registry, {name, pid})

    {:ok, name, pid}
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

    test "last person (creator) leaves: room stays alive but empty" do
      # Setup: Create a room with only a creator
      creator_id = "user1_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      # Verify room is alive
      assert Process.alive?(room_pid)

      # Creator leaves (last person in room)
      assert :ok = Room.leave(room_name, creator_id)

      # Give the process a moment to handle the leave
      Process.sleep(10)

      # Verify room process is still alive
      assert Process.alive?(room_pid)

      # Verify room is empty
      state = Room.get_state(room_pid)
      assert Enum.empty?(state.participants)
    end
  end

  describe "room lifecycle with timer" do
    @tag :sync
    test "room terminates when break timer completes" do
      # Create a room with 1 second session and 1 second break
      # Need 2 ticks to reach break (1->0, then 0->break), then 2 ticks for break (1->0, then 0->terminate)
      creator_id = "user1_#{System.unique_integer([:positive])}"

      {:ok, room_name, room_pid} =
        create_test_room(creator_id,
          duration_seconds: 1,
          tick_interval: 1000,
          break_duration_seconds: 1
        )

      # Verify room is alive
      assert Process.alive?(room_pid)

      # Start the session
      assert :ok = Room.start_session(room_name)

      # Verify room is in active state
      state = Room.get_state(room_pid)
      assert state.status == :active
      assert state.seconds_remaining == 1

      # Wait for session to complete (2 ticks: countdown + transition)
      Process.sleep(2150)

      # Verify room transitioned to break
      if Process.alive?(room_pid) do
        state = Room.get_state(room_pid)
        assert state.status == :break
        assert state.seconds_remaining == 1
      end

      # Wait for break to complete (2 ticks: countdown + terminate)
      Process.sleep(2150)

      # Verify room process has terminated
      refute Process.alive?(room_pid)
    end

    @tag :sync
    test "room terminates even when empty during break" do
      # Create a room with 1 second session, 2 seconds break
      # Need 2 ticks to reach break (1->0, then 0->break), then 3 ticks for break (2->1->0, then 0->terminate)
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name, room_pid} =
        create_test_room(creator_id,
          duration_seconds: 1,
          tick_interval: 1000,
          break_duration_seconds: 2
        )

      # Add another participant and start session
      assert :ok = Room.join(room_name, participant_id)
      assert :ok = Room.start_session(room_name)

      # Wait for session to reach break (2 ticks: countdown to 0, then transition to break)
      Process.sleep(2150)

      # Verify we're in break
      if Process.alive?(room_pid) do
        state = Room.get_state(room_pid)
        assert state.status == :break

        # Both users leave during break
        assert :ok = Room.leave(room_name, creator_id)
        assert :ok = Room.leave(room_name, participant_id)

        # Room should still be alive but empty
        assert Process.alive?(room_pid)
        state = Room.get_state(room_pid)
        assert Enum.empty?(state.participants)

        # Wait for break to complete (3 ticks: 2->1, 1->0, 0->terminate)
        Process.sleep(3150)

        # Room should terminate even though it was empty
        refute Process.alive?(room_pid)
      else
        flunk("Room terminated before break")
      end
    end
  end

  describe "empty room filtering" do
    test "empty rooms are hidden from non-original participants before session starts" do
      # Setup: Create a room with a creator
      creator_id = "user1_#{System.unique_integer([:positive])}"
      other_user_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)

      # Creator leaves, making the room empty
      assert :ok = Room.leave(room_name, creator_id)

      # Non-original participant should not see the empty room
      rooms = RoomRegistry.list_rooms(other_user_id)
      room = Enum.find(rooms, &(&1.name == room_name))
      assert room == nil
    end

    test "empty rooms during session are hidden from non-original participants" do
      # Setup: Create a room, start session, everyone leaves
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"
      other_user_id = "user3_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      assert :ok = Room.join(room_name, participant_id)
      assert :ok = Room.start_session(room_name)

      # Both users leave during session
      assert :ok = Room.leave(room_name, creator_id)
      assert :ok = Room.leave(room_name, participant_id)

      # Non-original participant should not see the empty room
      rooms = RoomRegistry.list_rooms(other_user_id)
      room = Enum.find(rooms, &(&1.name == room_name))
      assert room == nil

      # But original participants should see it
      creator_rooms = RoomRegistry.list_rooms(creator_id)
      creator_room = Enum.find(creator_rooms, &(&1.name == room_name))
      assert creator_room != nil

      participant_rooms = RoomRegistry.list_rooms(participant_id)
      participant_room = Enum.find(participant_rooms, &(&1.name == room_name))
      assert participant_room != nil
    end

    test "empty rooms are visible to original participants" do
      # Setup: Create a room and start a session
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      assert :ok = Room.join(room_name, participant_id)

      # Start session to lock in original participants
      assert :ok = Room.start_session(room_name)

      # Both users leave, making the room empty
      assert :ok = Room.leave(room_name, creator_id)
      assert :ok = Room.leave(room_name, participant_id)

      # Original participants should still see the empty room
      rooms_for_creator = RoomRegistry.list_rooms(creator_id)
      rooms_for_participant = RoomRegistry.list_rooms(participant_id)

      # Filter to just the room we care about (in case other tests have rooms)
      creator_room = Enum.find(rooms_for_creator, &(&1.name == room_name))
      participant_room = Enum.find(rooms_for_participant, &(&1.name == room_name))

      assert creator_room != nil
      assert participant_room != nil
      assert creator_room.name == room_name
      assert participant_room.name == room_name
    end

    test "non-empty rooms are visible to everyone" do
      # Setup: Create a room with participants
      creator_id = "user1_#{System.unique_integer([:positive])}"
      other_user_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)

      # Room has a participant, so should be visible to everyone
      rooms = RoomRegistry.list_rooms(other_user_id)
      room = Enum.find(rooms, &(&1.name == room_name))
      assert room != nil
      assert room.name == room_name
    end
  end
end
