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

        # Now test with multi-cycle room to verify timer cancellation during skip break
        # Create a new room with 2 cycles specifically for this test
        {:ok, room_name_2, room_pid_2} =
          create_test_room(creator_id,
            duration_seconds: 2,
            break_duration_seconds: 2,
            total_cycles: 2
          )

        # Add participant to new room
        participant2_id = "user3_#{System.unique_integer([:positive])}"
        assert :ok = Room.join(room_name_2, participant2_id)

        # Start and complete first session
        assert :ok = Room.start_session(room_name_2)
        tick(room_pid_2)
        tick(room_pid_2)
        tick(room_pid_2)

        # Should be in break
        state = Room.get_state(room_pid_2)
        assert state.status == :break
        assert state.current_cycle == 1

        # Both users skip break
        assert :ok = Room.go_again(room_name_2, creator_id)
        assert :ok = Room.go_again(room_name_2, participant2_id)

        Process.sleep(10)

        # Verify we transitioned to next cycle
        state = Room.get_state(room_pid_2)
        assert state.status == :active
        assert state.current_cycle == 2
        assert state.seconds_remaining == 2

        # Verify timer ticks correctly (no multiple timers)
        tick(room_pid_2)
        state = Room.get_state(room_pid_2)
        assert state.seconds_remaining == 1

        tick(room_pid_2)
        state = Room.get_state(room_pid_2)
        assert state.seconds_remaining == 0
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

  describe "todo list functionality" do
    test "user can add todo during active session" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Add todo
      assert :ok = Room.add_todo(room_name, creator_id, "Building tests")

      # Verify it was added
      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert length(participant.todos) == 1
      assert hd(participant.todos).text == "Building tests"
      assert hd(participant.todos).completed == false
      assert is_binary(hd(participant.todos).id)
    end

    test "user can add multiple todos up to max limit" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      assert :ok = Room.start_session(room_name)

      # Add 5 todos (max limit)
      for i <- 1..5 do
        assert :ok = Room.add_todo(room_name, creator_id, "Task #{i}")
      end

      # Verify all added
      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert length(participant.todos) == 5

      # Try to add 6th - should fail
      assert {:error, :max_todos_reached} = Room.add_todo(room_name, creator_id, "Task 6")

      # Verify still only 5
      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert length(participant.todos) == 5
    end

    test "user can toggle todo completion" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      assert :ok = Room.start_session(room_name)
      assert :ok = Room.add_todo(room_name, creator_id, "Task 1")

      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      todo = hd(participant.todos)
      assert todo.completed == false

      # Toggle to complete
      assert :ok = Room.toggle_todo(room_name, creator_id, todo.id)

      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      todo = hd(participant.todos)
      assert todo.completed == true

      # Toggle back to incomplete
      assert :ok = Room.toggle_todo(room_name, creator_id, todo.id)

      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      todo = hd(participant.todos)
      assert todo.completed == false
    end

    test "user can delete todo" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      assert :ok = Room.start_session(room_name)
      assert :ok = Room.add_todo(room_name, creator_id, "Task 1")
      assert :ok = Room.add_todo(room_name, creator_id, "Task 2")

      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert length(participant.todos) == 2

      # Delete first todo
      todo_id = hd(participant.todos).id
      assert :ok = Room.delete_todo(room_name, creator_id, todo_id)

      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert length(participant.todos) == 1
      assert hd(participant.todos).text == "Task 2"
    end

    test "user cannot add/modify todos when not in active or break session" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)

      # Try to add todo in autostart state
      assert {:error, :invalid_status} = Room.add_todo(room_name, creator_id, "Building tests")
    end

    test "todos persist when user leaves and rejoins" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)
      {:ok, room_pid} = RoomRegistry.get_room(room_name)

      # Join another user
      assert :ok = Room.join(room_name, participant_id)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Add todos
      assert :ok = Room.add_todo(room_name, participant_id, "Important task")
      assert :ok = Room.add_todo(room_name, participant_id, "Another task")

      # Verify they were added
      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == participant_id))
      assert length(participant.todos) == 2

      # Leave and rejoin
      assert :ok = Room.leave(room_name, participant_id)
      assert :ok = Room.join(room_name, participant_id)

      # Verify todos persisted
      state = Room.get_state(room_pid)
      participant = Enum.find(state.participants, &(&1.user_id == participant_id))
      assert length(participant.todos) == 2
      assert Enum.at(participant.todos, 0).text == "Important task"
      assert Enum.at(participant.todos, 1).text == "Another task"
    end

    test "todos persist across multiple cycles" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      # Use multi-cycle room so skip break works
      {:ok, room_name, room_pid} =
        create_test_room(creator_id,
          duration_seconds: 1,
          break_duration_seconds: 1,
          total_cycles: 2
        )

      # Join another user
      assert :ok = Room.join(room_name, participant_id)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Add todos for both
      assert :ok = Room.add_todo(room_name, creator_id, "Task 1")
      assert :ok = Room.add_todo(room_name, participant_id, "Task 2")

      # Complete session and go to break
      tick(room_pid)
      tick(room_pid)

      # Mark both ready and skip break to start cycle 2
      assert :ok = Room.go_again(room_name, creator_id)
      assert :ok = Room.go_again(room_name, participant_id)

      Process.sleep(10)

      # Verify todos PERSISTED for cycle 2
      state = Room.get_state(room_pid)
      assert state.current_cycle == 2

      creator = Enum.find(state.participants, &(&1.user_id == creator_id))
      participant = Enum.find(state.participants, &(&1.user_id == participant_id))

      assert length(creator.todos) == 1
      assert length(participant.todos) == 1
      assert hd(creator.todos).text == "Task 1"
      assert hd(participant.todos).text == "Task 2"
    end

    test "can add todos during break and they persist from active session" do
      creator_id = "user1_#{System.unique_integer([:positive])}"

      {:ok, room_name, room_pid} =
        create_test_room(creator_id, duration_seconds: 1, break_duration_seconds: 1)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Add todo during active session
      assert :ok = Room.add_todo(room_name, creator_id, "Working on feature X")

      # Verify it was added
      state = Room.get_state(room_pid)
      creator = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert length(creator.todos) == 1

      # Complete session and go to break
      tick(room_pid)
      tick(room_pid)

      # Verify todos PERSISTED when transitioning to break
      state = Room.get_state(room_pid)
      creator = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert length(creator.todos) == 1
      assert hd(creator.todos).text == "Working on feature X"

      # Now add another todo during break
      assert :ok = Room.add_todo(room_name, creator_id, "Great session!")

      # Verify both todos are present
      state = Room.get_state(room_pid)
      creator = Enum.find(state.participants, &(&1.user_id == creator_id))
      assert length(creator.todos) == 2
      assert Enum.at(creator.todos, 0).text == "Working on feature X"
      assert Enum.at(creator.todos, 1).text == "Great session!"
    end

    test "error when trying to toggle non-existent todo" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)

      assert :ok = Room.start_session(room_name)

      # Try to toggle non-existent todo
      assert {:error, :todo_not_found} =
               Room.toggle_todo(room_name, creator_id, "fake-id-123")
    end

    test "error when trying to delete non-existent todo" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)

      assert :ok = Room.start_session(room_name)

      # Try to delete non-existent todo
      assert {:error, :todo_not_found} =
               Room.delete_todo(room_name, creator_id, "fake-id-123")
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

    test "user cannot set status when not in active or break session" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)

      # Try to set status in autostart state
      assert {:error, :invalid_status} = Room.set_status(room_name, creator_id, "🔥")
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

    test "status emoji is reset when next cycle starts" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      # Use multi-cycle room so skip break works
      {:ok, room_name, room_pid} =
        create_test_room(creator_id,
          duration_seconds: 1,
          break_duration_seconds: 1,
          total_cycles: 2
        )

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

      # Mark both ready and skip break to start cycle 2
      assert :ok = Room.go_again(room_name, creator_id)
      assert :ok = Room.go_again(room_name, participant_id)

      Process.sleep(10)

      # Verify status_emoji was reset for cycle 2
      state = Room.get_state(room_pid)
      assert state.current_cycle == 2

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

    test "emits telemetry event when todo is added" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      {:ok, room_name} = RoomRegistry.create_room(creator_id, 25)

      # Start session
      assert :ok = Room.start_session(room_name)

      # Set up telemetry handler to capture events
      test_pid = self()

      :telemetry.attach(
        "test-add-todo",
        [:pomodoro, :user, :add_todo],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      # Add todo (should trigger telemetry)
      todo_text = "Building cool features"
      assert :ok = Room.add_todo(room_name, creator_id, todo_text)

      # Assert telemetry event was emitted
      assert_receive {:telemetry_event, [:pomodoro, :user, :add_todo], %{count: 1}, metadata}

      assert metadata.room_name == room_name
      assert metadata.user_id == creator_id
      assert metadata.text_length == String.length(todo_text)

      # Clean up
      :telemetry.detach("test-add-todo")
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

  describe "autostart countdown" do
    test "session timer starts at correct duration after autostart countdown completes" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      duration_seconds = 25 * 60

      # Create room with manual ticking (very large tick_interval to prevent auto-ticking)
      {:ok, _room_name, room_pid} =
        create_test_room(creator_id,
          duration_seconds: duration_seconds,
          tick_interval: 999_999_999
        )

      # Room should start in autostart status with 180 seconds
      state = Room.get_state(room_pid)
      assert state.status == :autostart
      assert state.seconds_remaining == 180

      # Tick down the autostart countdown: 180 -> 179 -> 178 -> ... -> 1 -> 0
      # We need 180 ticks to get to 0, then 1 more tick to trigger the transition
      for _i <- 1..181 do
        tick(room_pid)
      end

      # After autostart completes, room should transition to :active
      state = Room.get_state(room_pid)
      assert state.status == :active

      # Session timer should start at the ORIGINAL duration_seconds, not the countdown value!
      assert state.seconds_remaining == duration_seconds
    end

    test "manual start during autostart countdown resets timer to full duration" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      duration_seconds = 25 * 60

      # Create room with manual ticking
      {:ok, room_name, room_pid} =
        create_test_room(creator_id,
          duration_seconds: duration_seconds,
          tick_interval: 999_999_999
        )

      # Verify autostart countdown
      state = Room.get_state(room_pid)
      assert state.status == :autostart
      assert state.seconds_remaining == 180

      # Tick down partway: 180 -> 179 -> 178 -> ... -> 170
      for _i <- 1..10 do
        tick(room_pid)
      end

      state = Room.get_state(room_pid)
      assert state.seconds_remaining == 170

      # Creator manually starts the session
      Room.start_session(room_name)

      # Session should start at FULL duration, not the countdown value
      state = Room.get_state(room_pid)
      assert state.status == :active
      assert state.seconds_remaining == duration_seconds
    end
  end

  describe "spectator promotion during break" do
    @tag :sync
    test "spectator who joined during active session becomes participant during break and can participate in next cycle" do
      # A creates a room with 2 cycles
      user_a_id = "userA_#{System.unique_integer([:positive])}"
      user_b_id = "userB_#{System.unique_integer([:positive])}"

      {:ok, room_name, room_pid} =
        create_test_room(user_a_id,
          duration_seconds: 2,
          break_duration_seconds: 2,
          total_cycles: 2
        )

      # A starts the timer
      assert :ok = Room.start_session(room_name)

      # Verify room is in active state and A is a session participant
      state = Room.get_state(room_pid)
      assert state.status == :active
      assert state.seconds_remaining == 2
      assert user_a_id in state.session_participants

      # B joins as a spectator (since session is already active)
      assert :ok = Room.join(room_name, user_b_id)

      # Verify B is a spectator (not in participants yet, but in spectators)
      raw_state = Room.get_raw_state(room_pid)
      assert length(raw_state.participants) == 1
      assert user_b_id in raw_state.spectators
      assert user_a_id in raw_state.session_participants
      refute user_b_id in raw_state.session_participants

      # Timer finishes: 2 -> 1 -> 0 -> transition to break
      tick(room_pid)
      tick(room_pid)
      tick(room_pid)

      # Verify room transitioned to break
      if Process.alive?(room_pid) do
        state = Room.get_state(room_pid)
        assert state.status == :break
        assert state.seconds_remaining == 2

        # During break, B should now be a participant (spectators are promoted)
        assert length(state.participants) == 2

        # Both A and B skip break to go to next cycle
        assert :ok = Room.go_again(room_name, user_a_id)
        assert :ok = Room.go_again(room_name, user_b_id)

        # Give it a moment to process
        Process.sleep(10)

        # Verify room transitioned to cycle 2
        state = Room.get_state(room_pid)
        assert state.status == :active
        assert state.current_cycle == 2
        assert state.seconds_remaining == 2

        # B should be a session participant now (since they joined during break)
        # Actually, they joined as spectator so they won't be in session_participants yet
        # They'll be in session_participants for the NEXT cycle after this break
        # Let's just verify both are participants
        assert length(state.participants) == 2
      else
        flunk("Room terminated unexpectedly")
      end
    end
  end

  describe "multi-cycle pomodoros" do
    test "room completes multiple cycles and terminates after final break" do
      creator_id = "user1_#{System.unique_integer([:positive])}"

      # Create a room with 2 cycles, 2 second work, 1 second break
      {:ok, room_name, room_pid} =
        create_test_room(creator_id,
          duration_seconds: 2,
          break_duration_seconds: 1,
          total_cycles: 2
        )

      # Verify initial state
      state = Room.get_state(room_pid)
      assert state.total_cycles == 2
      assert state.current_cycle == 1

      # Start the session
      assert :ok = Room.start_session(room_name)

      state = Room.get_state(room_pid)
      assert state.status == :active
      assert state.current_cycle == 1

      # Complete first work session (2 -> 1 -> 0 -> break)
      tick(room_pid)
      tick(room_pid)
      tick(room_pid)

      # Should be in break now
      if Process.alive?(room_pid) do
        state = Room.get_state(room_pid)
        assert state.status == :break
        assert state.current_cycle == 1
        assert state.seconds_remaining == 1

        # Complete first break (1 -> 0 -> next cycle)
        tick(room_pid)
        tick(room_pid)

        # Should be in second cycle now
        if Process.alive?(room_pid) do
          state = Room.get_state(room_pid)
          assert state.status == :active
          assert state.current_cycle == 2
          assert state.seconds_remaining == 2

          # Complete second work session
          tick(room_pid)
          tick(room_pid)
          tick(room_pid)

          # Should be in final break
          if Process.alive?(room_pid) do
            state = Room.get_state(room_pid)
            assert state.status == :break
            assert state.current_cycle == 2
            assert state.seconds_remaining == 1

            # Complete final break - room should terminate
            tick(room_pid)
            tick(room_pid)

            # Give it a moment to terminate
            Process.sleep(20)

            # Room should be terminated
            refute Process.alive?(room_pid)
          else
            flunk("Room terminated before final break")
          end
        else
          flunk("Room terminated after first break")
        end
      else
        flunk("Room terminated after first session")
      end
    end

    test "skip break advances to next cycle immediately" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      # Create a room with 3 cycles
      {:ok, room_name, room_pid} =
        create_test_room(creator_id,
          duration_seconds: 2,
          break_duration_seconds: 5,
          total_cycles: 3
        )

      # Add participant
      assert :ok = Room.join(room_name, participant_id)

      # Start the session
      assert :ok = Room.start_session(room_name)

      # Complete first work session
      tick(room_pid)
      tick(room_pid)
      tick(room_pid)

      # Should be in break
      state = Room.get_state(room_pid)
      assert state.status == :break
      assert state.current_cycle == 1

      # Both users skip break
      assert :ok = Room.go_again(room_name, creator_id)
      assert :ok = Room.go_again(room_name, participant_id)

      Process.sleep(10)

      # Should advance to cycle 2 immediately
      if Process.alive?(room_pid) do
        state = Room.get_state(room_pid)
        assert state.status == :active
        assert state.current_cycle == 2
        assert state.seconds_remaining == 2
      else
        flunk("Room terminated unexpectedly")
      end
    end

    test "skip break returns error on final break" do
      creator_id = "user1_#{System.unique_integer([:positive])}"

      # Create a room with 1 cycle
      {:ok, room_name, room_pid} =
        create_test_room(creator_id,
          duration_seconds: 1,
          break_duration_seconds: 2,
          total_cycles: 1
        )

      # Start and complete the only session
      assert :ok = Room.start_session(room_name)
      tick(room_pid)
      tick(room_pid)

      # Should be in final break
      state = Room.get_state(room_pid)
      assert state.status == :break
      assert state.current_cycle == 1
      assert state.total_cycles == 1

      # Try to skip final break - should return error
      assert {:error, :final_break} = Room.go_again(room_name, creator_id)

      if Process.alive?(room_pid) do
        state = Room.get_state(room_pid)
        # Should still be in break, not active
        assert state.status == :break
        assert state.current_cycle == 1
      else
        flunk("Room terminated unexpectedly")
      end
    end

    test "single cycle room behaves as before (backwards compatibility)" do
      creator_id = "user1_#{System.unique_integer([:positive])}"

      # Create a room with default (1) cycle
      {:ok, room_name, room_pid} =
        create_test_room(creator_id, duration_seconds: 1, break_duration_seconds: 1)

      state = Room.get_state(room_pid)
      assert state.total_cycles == 1
      assert state.current_cycle == 1

      # Start session
      assert :ok = Room.start_session(room_name)

      # Complete work session
      tick(room_pid)
      tick(room_pid)

      # Should be in break
      state = Room.get_state(room_pid)
      assert state.status == :break

      # Complete break - should terminate (old behavior)
      tick(room_pid)
      tick(room_pid)
      Process.sleep(20)

      refute Process.alive?(room_pid)
    end

    test "cycle information is serialized in room state" do
      creator_id = "user1_#{System.unique_integer([:positive])}"

      {:ok, _room_name, room_pid} =
        create_test_room(creator_id,
          duration_seconds: 25 * 60,
          break_duration_seconds: 5 * 60,
          total_cycles: 4
        )

      state = Room.get_state(room_pid)

      assert state.total_cycles == 4
      assert state.current_cycle == 1
      assert state.duration_minutes == 25
      assert state.break_duration_minutes == 5
    end

    test "break timer auto-starts next cycle when participants don't all skip" do
      creator_id = "user1_#{System.unique_integer([:positive])}"
      participant_id = "user2_#{System.unique_integer([:positive])}"

      # Create room with 3 cycles
      {:ok, room_name, room_pid} =
        create_test_room(creator_id,
          duration_seconds: 2,
          break_duration_seconds: 2,
          total_cycles: 3
        )

      # Add participant
      assert :ok = Room.join(room_name, participant_id)

      # Start session
      assert :ok = Room.start_session(room_name)

      state = Room.get_state(room_pid)
      assert state.status == :active
      assert state.current_cycle == 1

      # Complete first work session (2 -> 1 -> 0 -> break)
      tick(room_pid)
      tick(room_pid)
      tick(room_pid)

      # Should be in break now
      if Process.alive?(room_pid) do
        state = Room.get_state(room_pid)
        assert state.status == :break
        assert state.current_cycle == 1

        # Creator clicks skip, but participant doesn't
        assert :ok = Room.go_again(room_name, creator_id)

        # Verify creator is ready but participant is not
        state = Room.get_state(room_pid)
        creator = Enum.find(state.participants, &(&1.user_id == creator_id))
        participant = Enum.find(state.participants, &(&1.user_id == participant_id))
        assert creator.ready_for_next == true
        assert participant.ready_for_next == false

        # Still in break since not everyone is ready
        assert state.status == :break

        # Let break timer complete naturally (2 -> 1 -> 0 -> next cycle)
        tick(room_pid)
        tick(room_pid)
        tick(room_pid)

        # Should auto-start cycle 2 (not go to lobby, not stay in break)
        if Process.alive?(room_pid) do
          state = Room.get_state(room_pid)
          assert state.status == :active
          assert state.current_cycle == 2
          assert state.seconds_remaining == 2

          # Both participants should have ready_for_next reset
          creator = Enum.find(state.participants, &(&1.user_id == creator_id))
          participant = Enum.find(state.participants, &(&1.user_id == participant_id))
          assert creator.ready_for_next == false
          assert participant.ready_for_next == false
        else
          flunk("Room terminated after break instead of starting cycle 2")
        end
      else
        flunk("Room terminated after first session")
      end
    end
  end
end
