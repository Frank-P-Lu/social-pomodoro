# Social Pomodoro - Project Context

## Overview
A real-time multiplayer pomodoro app built with Phoenix LiveView. Users can focus together with strangers in synchronized sessions.

## Tech Stack
- **Phoenix LiveView** - Real-time UI without JavaScript frameworks
- **GenServers** - State management for rooms and user registry
- **PubSub** - Real-time updates across clients
- **ETS** - In-memory storage (no database for MVP)
- **Tailwind CSS** - Styling

## Core Concept
Focus with strangers. Queue up in a lobby, join or create rooms, and run pomodoro sessions together with emoji reactions and shared breaks.

## Architecture

### State Management
- **UserRegistry GenServer** - Maps `user_id → username` (ETS-backed)
  - User IDs are persistent (cookie-based)
  - Usernames are editable and live in this registry
  - Broadcasts username updates via PubSub

- **RoomRegistry GenServer** - Tracks all active rooms (ETS-backed)
  - Creates and removes rooms
  - Returns list of all rooms for lobby

- **Room GenServer** - One per room
  - Manages participants (by user_id)
  - Handles timer (1-second ticks)
  - Tracks status: `:waiting`, `:active`, `:break`
  - Broadcasts state changes via PubSub

### User Identity Pattern
**Cookie → user_id → username lookup**

1. Plug generates/reads `user_id` from cookie (persistent across sessions)
2. Plug puts `user_id` in session for LiveView access
3. LiveView reads `user_id` from session
4. LiveView fetches current `username` from UserRegistry
5. Username updates go to UserRegistry, all clients get update via PubSub

**Benefits:**
- Persistent identity even if you refresh mid-session
- Username changes propagate to all clients in real-time
- Rooms store user_id (immutable) not username (mutable)

### Pages

**LobbyLive** (`/`)
- Shows available rooms (waiting/in-progress)
- Create room with custom duration (5 min - 3 hours)
- Edit username (updates UserRegistry)
- Join waiting rooms or see locked active rooms

**SessionLive** (`/room/:room_id`)
- Waiting state: Shows participants, "Start" button for creator
- Active state: Countdown timer, emoji reactions (🔥💪⚡🎯)
- Break state: 5-minute auto-break, "Go again" or "Return to lobby"

## Key Flows

### Creating a Room
1. User sets duration via slider/presets
2. Click "Create Room" → RoomRegistry spawns Room GenServer
3. Room appears in lobby with special border (your room)
4. Shows "Start" button instead of "Join"

### Joining a Room
1. Click "Join" on waiting room
2. Room GenServer adds user_id to participants
3. Broadcasts update → all clients see new participant avatar

### Session Flow
1. Creator clicks "Start" → Room transitions to `:active`
2. Timer counts down every second, broadcasts state
3. Users can send emoji reactions (broadcast to all)
4. Timer hits 0 → auto-transition to `:break` (5 minutes)
5. During break: click "Go again" (marks user as ready)
6. When all ready → auto-start new session with same duration
7. Or click "Return to lobby" → leave room

### Username Updates
1. User types in input, clicks "Update"
2. LiveView calls `UserRegistry.set_username(user_id, new_name)`
3. UserRegistry broadcasts `{:username_updated, user_id, username}`
4. All LiveViews subscribed to that user update their displays
5. Cookie/session unchanged (user_id is permanent)

## File Structure

```
lib/
├── social_pomodoro/
│   ├── application.ex          # Supervision tree
│   ├── room.ex                 # Room GenServer (timer, participants, state)
│   ├── room_registry.ex        # Tracks all rooms
│   └── user_registry.ex        # user_id → username mapping
├── social_pomodoro_web/
│   ├── live/
│   │   ├── lobby_live.ex       # Home/lobby page
│   │   └── session_live.ex     # Active session page
│   ├── plugs/
│   │   └── username_session.ex # Generates/reads user_id from cookie
│   └── router.ex
```

## Data Models

### Room State
```elixir
%{
  room_id: String.t(),
  creator: String.t(),          # user_id
  duration_minutes: integer(),
  status: :waiting | :active | :break,
  participants: [%{user_id: String.t(), ready_for_next: boolean()}],
  seconds_remaining: integer() | nil,
  reactions: [%{user_id: String.t(), emoji: String.t(), timestamp: integer()}],
  break_duration_minutes: 5
}
```

### User Identity
- **user_id**: Random string, stored in cookie, never changes
- **username**: Editable friendly name (e.g., "HappyPanda42"), stored in UserRegistry

## Design Decisions

### No Database
All state in memory (GenServers + ETS). Rooms/users disappear on server restart. This is intentional for MVP - keeps it lightweight.

### User ID Pattern
Chose cookie-based user_id instead of just username-in-cookie because:
- Allows username changes without losing identity
- Rooms can track user_id (stable) not username (changes)
- User can refresh mid-session and rejoin with same identity

### Real-time Updates
PubSub topics:
- `"rooms"` - Room list updates (create/delete/state changes)
- `"room:#{room_id}"` - Room-specific updates (timer, reactions, participants)
- `"user:#{user_id}"` - Username updates for a specific user

## Running the App

```bash
mix phx.server
```

Visit http://localhost:4000

## MVP Constraints
- No authentication/accounts
- No persistence (in-memory only)
- Single server (no distributed state)
- No spam protection on emoji reactions
- No room size limits
