# Visual Preview - Pomodoro Completion Message Changes

## Break Screen Layout

The break screen appears after a Pomodoro session completes. Here's what changes:

### BEFORE - Original Message

```
┌────────────────────────────────────────────────────┐
│                                                    │
│                      🎉                            │
│                                                    │
│                  Great Work!                       │
│                                                    │
│   You just focused for 25 minutes with 1 person!  │  ← ❌ Awkward for solo
│                                                    │
│                    0:05                            │
│              Break time remaining                  │
│                                                    │
│              [User Avatar]                         │
│                                                    │
│         [Go Again Together]  [Return to Lobby]    │
│                                                    │
└────────────────────────────────────────────────────┘
```

### AFTER - Solo Session (1 participant)

```
┌────────────────────────────────────────────────────┐
│                                                    │
│                      🎉                            │
│                                                    │
│                  Great Work!                       │
│                                                    │
│              You focused solo!                     │  ← ✅ One of 4 random messages
│                                                    │
│                    0:05                            │
│              Break time remaining                  │
│                                                    │
│              [User Avatar]                         │
│                                                    │
│         [Go Again Together]  [Return to Lobby]    │
│                                                    │
└────────────────────────────────────────────────────┘
```

Other possible messages:
- "Flying solo today - nice work!"
- "Solo focus session complete!"
- "You stayed focused!"

### AFTER - Group Session (2 participants)

```
┌────────────────────────────────────────────────────┐
│                                                    │
│                      🎉                            │
│                                                    │
│                  Great Work!                       │
│                                                    │
│        You focused with 1 other person!            │  ← ✅ Clear messaging
│                                                    │
│                    0:05                            │
│              Break time remaining                  │
│                                                    │
│           [Avatar 1]    [Avatar 2]                 │
│                                                    │
│         [Go Again Together]  [Return to Lobby]    │
│                                                    │
└────────────────────────────────────────────────────┘
```

### AFTER - Group Session (4 participants)

```
┌────────────────────────────────────────────────────┐
│                                                    │
│                      🎉                            │
│                                                    │
│                  Great Work!                       │
│                                                    │
│        You focused with 3 other people!            │  ← ✅ Counts others, not total
│                                                    │
│                    0:05                            │
│              Break time remaining                  │
│                                                    │
│     [Avatar 1] [Avatar 2] [Avatar 3] [Avatar 4]   │
│                                                    │
│         [Go Again Together]  [Return to Lobby]    │
│                                                    │
└────────────────────────────────────────────────────┘
```

## Key Improvements

1. **Solo Sessions**: No longer says "with 1 person" which was confusing
2. **Group Sessions**: Says "X other people" making it clear you're not counting yourself
3. **Variety**: 4 different encouraging messages for solo sessions
4. **Grammar**: Properly handles "1 other person" vs "2+ other people"

## Message Examples

| Participants | Old Message | New Message |
|--------------|-------------|-------------|
| 1 | "You just focused for 25 minutes with 1 person!" | "You focused solo!" (random) |
| 2 | "You just focused for 25 minutes with 2 people!" | "You focused with 1 other person!" |
| 3 | "You just focused for 25 minutes with 3 people!" | "You focused with 2 other people!" |
| 5 | "You just focused for 25 minutes with 5 people!" | "You focused with 4 other people!" |

## Code Location

The message is displayed in the `break_view` function in:
`lib/social_pomodoro_web/live/session_live.ex`

Line 278:
```elixir
{completion_message(@room_state.duration_minutes, length(@room_state.participants))}
```
