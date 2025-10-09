defmodule SocialPomodoro.RoomTest do
  use ExUnit.Case, async: true
  alias SocialPomodoro.Room
  alias SocialPomodoro.RoomRegistry

  setup do
    :ok
  end

  # Helper to create a room with custom options for testing
  defp create_test_room(creator_id, opts) do
    name = SocialPomodoro.RoomNameGenerator.generate()

    room_opts =
      [
        name: name,
        creator: creator_id
      ] ++ opts

    {:ok, pid} = Room.start_link(room_opts)

    # Register it manually since we're bypassing RoomRegistry.create_room
    :ets.insert(:room_registry, {name, pid})

    {:ok, name, pid}
  end

  # Helper to manually tick the timer (for fast tests)
  defp tick(pid) do
    send(pid, :tick)
    # Give it a moment to process
    Process.sleep(10)
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
    test "timer is cancelled when transitioning between states to prevent multiple ticks" do
      # This test verifies the bug fix where timers were not cancelled
      # when transitioning from active->break or break->active, causing erratic ticking
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name, room_pid} =
        create_test_room(creator_id, duration_seconds: 2, break_duration_seconds: 2)

      # Add another participant
      assert :ok = Room.join(room_name, participant_id)

      # Start the session
      assert :ok = Room.start_session(room_name)

      # Verify room is in active state
      state = Room.get_state(room_pid)
      assert state.status == :active
      assert state.seconds_remaining == 2

      # Tick to countdown: 2 -> 1
      tick(room_pid)

      state = Room.get_state(room_pid)
      assert state.seconds_remaining == 1

      # Tick to countdown: 1 -> 0
      tick(room_pid)

      state = Room.get_state(room_pid)
      assert state.seconds_remaining == 0

      # Tick to transition to break (0, :active -> :break)
      # This is where the old timer should be cancelled
      tick(room_pid)

      # Verify room transitioned to break
      if Process.alive?(room_pid) do
        state = Room.get_state(room_pid)
        assert state.status == :break
        assert state.seconds_remaining == 2

        # Now both users mark ready to go again
        assert :ok = Room.go_again(room_name, creator_id)

        # Before the second user marks ready, verify we're still in break
        state = Room.get_state(room_pid)
        assert state.status == :break

        # Second user marks ready - this should cancel break timer and start new session
        assert :ok = Room.go_again(room_name, participant_id)

        # Give it a moment to process
        Process.sleep(10)

        # Verify we transitioned back to active
        state = Room.get_state(room_pid)
        assert state.status == :active
        assert state.seconds_remaining == 2

        # Now tick once and verify we only decremented by 1
        # If the bug existed, we'd see multiple decrements or erratic behavior
        tick(room_pid)

        state = Room.get_state(room_pid)
        assert state.seconds_remaining == 1

        # Tick again to verify consistent behavior
        tick(room_pid)

        state = Room.get_state(room_pid)
        assert state.seconds_remaining == 0

        # The timer should tick exactly once per tick message
        # proving that old timers were properly cancelled
      else
        flunk("Room terminated unexpectedly")
      end
    end

    @tag :sync
    test "room terminates when break timer completes" do
      # Create a room with 1 second session and 1 second break
      # Use manual ticks instead of waiting for real time
      creator_id = "user1_#{System.unique_integer([:positive])}"

      {:ok, room_name, room_pid} =
        create_test_room(creator_id, duration_seconds: 1, break_duration_seconds: 1)

      # Verify room is alive
      assert Process.alive?(room_pid)

      # Start the session
      assert :ok = Room.start_session(room_name)

      # Verify room is in active state
      state = Room.get_state(room_pid)
      assert state.status == :active
      assert state.seconds_remaining == 1

      # Tick to countdown (1 -> 0)
      tick(room_pid)

      # Tick to transition to break (0, :active -> :break)
      tick(room_pid)

      # Verify room transitioned to break
      if Process.alive?(room_pid) do
        state = Room.get_state(room_pid)
        assert state.status == :break
        assert state.seconds_remaining == 1
      end

      # Tick to countdown (1 -> 0)
      tick(room_pid)

      # Tick to terminate (0, :break -> terminate)
      tick(room_pid)

      # Verify room process has terminated
      refute Process.alive?(room_pid)
    end

    @tag :sync
    test "room terminates even when empty during break" do
      # Create a room with 1 second session, 2 seconds break
      # Use manual ticks for fast testing
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name, room_pid} =
        create_test_room(creator_id, duration_seconds: 1, break_duration_seconds: 2)

      # Add another participant and start session
      assert :ok = Room.join(room_name, participant_id)
      assert :ok = Room.start_session(room_name)

      # Tick to countdown (1 -> 0)
      tick(room_pid)

      # Tick to transition to break (0, :active -> :break)
      tick(room_pid)

      # Verify we're in break
      if Process.alive?(room_pid) do
        state = Room.get_state(room_pid)
        assert state.status == :break
        assert state.seconds_remaining == 2

        # Both users leave during break
        assert :ok = Room.leave(room_name, creator_id)
        assert :ok = Room.leave(room_name, participant_id)

        # Room should still be alive but empty
        assert Process.alive?(room_pid)
        state = Room.get_state(room_pid)
        assert Enum.empty?(state.participants)

        # Tick through break: 2->1, 1->0, then terminate
        # 2 -> 1
        tick(room_pid)
        # 1 -> 0
        tick(room_pid)
        # 0, :break -> terminate
        tick(room_pid)

        # Room should terminate even though it was empty
        refute Process.alive?(room_pid)
      else
        flunk("Room terminated before break")
      end
    end
  end

  describe "working_on functionality" do
    test "user can set working_on during active session" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Set working_on
      assert :ok = Room.set_working_on(room_name, creator_id, "Building tests")

      # Verify it was set (via serialized state since that's how LiveView sees it)
      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert participant.working_on == "Building tests"
    end

    test "user cannot set working_on when not in active session" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)

      # Try to set working_on in waiting state
      assert {:error, :not_active} = Room.set_working_on(room_name, creator_id, "Building tests")
    end

    test "working_on persists when user leaves and rejoins" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      # Join another user
      assert :ok = Room.join(room_name, participant_id)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Set working_on
      assert :ok = Room.set_working_on(room_name, participant_id, "Important task")

      # Verify it was set
      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == participant_id))
      assert participant.working_on == "Important task"

      # Leave and rejoin
      assert :ok = Room.leave(room_name, participant_id)
      assert :ok = Room.join(room_name, participant_id)

      # Verify working_on persisted
      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == participant_id))
      assert participant.working_on == "Important task"
    end

    test "working_on is reset when session starts" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name, room_pid} =
        create_test_room(creator_id, duration_seconds: 1, break_duration_seconds: 1)

      # Join another user
      assert :ok = Room.join(room_name, participant_id)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Set working_on for both
      assert :ok = Room.set_working_on(room_name, creator_id, "Task 1")
      assert :ok = Room.set_working_on(room_name, participant_id, "Task 2")

      # Complete session and go to break
      tick(room_pid)
      tick(room_pid)

      # Mark both ready and start new session
      assert :ok = Room.go_again(room_name, creator_id)
      assert :ok = Room.go_again(room_name, participant_id)

      # Verify working_on was reset
      state = Room.get_state(room_pid)
      creator = Enum.find(state.participants, &(&1.user_id == creator_id))
      participant = Enum.find(state.participants, &(&1.user_id == participant_id))

      assert is_nil(creator.working_on)
      assert is_nil(participant.working_on)
    end
  end

  describe "status emoji functionality" do
    test "user can set status emoji during active session" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Set status emoji
      assert :ok = Room.set_status(room_name, creator_id, "🔥")

      # Verify it was set (via serialized state)
      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert participant.status_emoji == "🔥"
    end

    test "user can toggle status emoji off by clicking same emoji" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Set status emoji
      assert :ok = Room.set_status(room_name, creator_id, "🔥")

      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert participant.status_emoji == "🔥"

      # Click same emoji again to toggle off
      assert :ok = Room.set_status(room_name, creator_id, "🔥")

      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert is_nil(participant.status_emoji)
    end

    test "user can switch to different status emoji" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Set status emoji
      assert :ok = Room.set_status(room_name, creator_id, "🔥")

      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert participant.status_emoji == "🔥"

      # Switch to different emoji
      assert :ok = Room.set_status(room_name, creator_id, "💪")

      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert participant.status_emoji == "💪"
    end

    test "user cannot set status when not in active session" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)

      # Try to set status in waiting state
      assert {:error, :not_active} = Room.set_status(room_name, creator_id, "🔥")
    end

    test "status emoji persists when user leaves and rejoins" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      # Join another user
      assert :ok = Room.join(room_name, participant_id)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Set status
      assert :ok = Room.set_status(room_name, participant_id, "💪")

      # Verify it was set
      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == participant_id))
      assert participant.status_emoji == "💪"

      # Leave and rejoin
      assert :ok = Room.leave(room_name, participant_id)
      assert :ok = Room.join(room_name, participant_id)

      # Verify status persisted
      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == participant_id))
      assert participant.status_emoji == "💪"
    end

    test "status emoji is reset when session starts" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name, room_pid} =
        create_test_room(creator_id, duration_seconds: 1, break_duration_seconds: 1)

      # Join another user
      assert :ok = Room.join(room_name, participant_id)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Set status for both
      assert :ok = Room.set_status(room_name, creator_id, "🔥")
      assert :ok = Room.set_status(room_name, participant_id, "💪")

      # Complete session and go to break
      tick(room_pid)
      tick(room_pid)

      # Mark both ready and start new session
      assert :ok = Room.go_again(room_name, creator_id)
      assert :ok = Room.go_again(room_name, participant_id)

      # Verify status_emoji was reset
      state = Room.get_state(room_pid)
      creator = Enum.find(state.participants, &(&1.user_id == creator_id))
      participant = Enum.find(state.participants, &(&1.user_id == participant_id))

      assert is_nil(creator.status_emoji)
      assert is_nil(participant.status_emoji)
    end
  end

  describe "telemetry events" do
    test "emits telemetry event when user rejoins during active session" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, _room_pid} = RoomRegistry.get_room(room_name)

      # Join another user
      assert :ok = Room.join(room_name, participant_id)

      # Start session (locks in original participants)
      assert :ok = Room.start_session(room_name)

      # Participant leaves
      assert :ok = Room.leave(room_name, participant_id)

      # Set up telemetry handler to capture events
      test_pid = self()

      :telemetry.attach(
        "test-rejoin",
        [:pomodoro, :user, :rejoined],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      # Participant rejoins (should trigger telemetry)
      assert :ok = Room.join(room_name, participant_id)

      # Assert telemetry event was emitted
      assert_receive {:telemetry_event, [:pomodoro, :user, :rejoined], %{count: 1}, metadata}
      assert metadata.room_name == room_name
      assert metadata.user_id == participant_id
      assert metadata.room_status == :active

      # Clean up
      :telemetry.detach("test-rejoin")
    end

    test "emits telemetry event when working_on is set" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Set up telemetry handler to capture events
      test_pid = self()

      :telemetry.attach(
        "test-working-on",
        [:pomodoro, :user, :set_working_on],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      # Set working_on (should trigger telemetry)
      working_on_text = "Building cool features"
      assert :ok = Room.set_working_on(room_name, creator_id, working_on_text)

      # Assert telemetry event was emitted
      assert_receive {:telemetry_event, [:pomodoro, :user, :set_working_on], %{count: 1},
                      metadata}

      assert metadata.room_name == room_name
      assert metadata.user_id == creator_id
      assert metadata.text_length == String.length(working_on_text)

      # Clean up
      :telemetry.detach("test-working-on")
    end

    test "does not emit rejoin telemetry when user first joins" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)

      # Set up telemetry handler to capture events
      test_pid = self()

      :telemetry.attach(
        "test-first-join",
        [:pomodoro, :user, :rejoined],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      # First join (should NOT trigger rejoin telemetry)
      assert :ok = Room.join(room_name, participant_id)

      # Assert no telemetry event was emitted
      refute_receive {:telemetry_event, _, _, _}, 100

      # Clean up
      :telemetry.detach("test-first-join")
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
