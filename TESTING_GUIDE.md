# Manual Testing Guide - Pomodoro Completion Message

## Changes Made

Updated the completion message shown when a Pomodoro session finishes to:
1. Show "You focused with X other people!" where X = total participants - 1 (for group sessions)
2. Show one of 4 random encouraging messages for solo sessions

## Test Scenarios

### Scenario 1: Solo Session
**Steps:**
1. Start the Phoenix server: `mix phx.server`
2. Open browser to `localhost:4000`
3. Create a new room
4. Start the session (without any other participants joining)
5. Wait for the timer to complete OR manually set a short timer for testing
6. Verify the break screen shows ONE of the following messages:
   - "You focused solo!"
   - "Flying solo today - nice work!"
   - "Solo focus session complete!"
   - "You stayed focused!"

**Expected Result:** A random solo message is displayed (NOT "You just focused for X minutes with 1 person!")

### Scenario 2: Two Participants
**Steps:**
1. Open two browser tabs/windows (or use incognito mode for second user)
2. In Tab 1: Create a new room
3. In Tab 2: Join the same room from the lobby
4. In Tab 1: Start the session
5. Wait for timer to complete
6. Verify BOTH users see: "You focused with 1 other person!"

**Expected Result:** Message shows "1 other person" (singular form)

### Scenario 3: Three or More Participants
**Steps:**
1. Open three or more browser tabs/windows
2. Create a room in first tab
3. Join the room from the other tabs
4. Start the session
5. Wait for timer to complete
6. Verify ALL users see: "You focused with X other people!" where X = (total participants - 1)

**Expected Result:** 
- For 3 participants: "You focused with 2 other people!"
- For 4 participants: "You focused with 3 other people!"
- etc.

## Code Changes Summary

### File: `lib/social_pomodoro_web/live/session_live.ex`

#### Added Function:
```elixir
defp completion_message(duration_minutes, participant_count) do
  cond do
    participant_count == 1 ->
      # Random message for solo sessions
      Enum.random([
        "You focused solo!",
        "Flying solo today - nice work!",
        "Solo focus session complete!",
        "You stayed focused!"
      ])

    true ->
      # Message for group sessions
      other_count = participant_count - 1
      "You focused with #{other_count} #{if other_count == 1, do: "other person", else: "other people"}!"
  end
end
```

#### Modified Function:
```elixir
defp break_view(assigns) do
  # Changed from:
  # You just focused for {@room_state.duration_minutes} minutes with {length(@room_state.participants)} {if length(@room_state.participants) == 1, do: "person", else: "people"}!
  
  # To:
  {completion_message(@room_state.duration_minutes, length(@room_state.participants))}
end
```

## Regression Testing

Ensure the following still work correctly:
- [ ] Timer countdown displays correctly during active session
- [ ] Break time countdown displays correctly
- [ ] Participant avatars show correctly
- [ ] "Go Again Together" button works for all participants
- [ ] "Return to Lobby" button works correctly
- [ ] Ready status indicators work when participants click "Go Again Together"
