# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Social Pomodoro is a real-time collaborative pomodoro timer application built with Phoenix LiveView. Users can create or join rooms to work together in synchronized focus sessions with breaks, todos, status updates, and chat.

## Commands

**Note**: The development server is likely already running. Do not restart it unless there's a specific reason (e.g., dependency changes, application.ex modifications, or user requests it).

### Development
- `mix phx.server` - Start the Phoenix server (auto-approved, runs on port 4000)
- `iex -S mix phx.server` - Start with interactive Elixir shell
- `mix setup` - Install dependencies and setup assets

### Testing
- `mix test` - Run all tests (auto-approved)
- `mix test test/path/to/test.exs` - Run specific test file
- `mix test --failed` - Run previously failed tests
- E2E tests are excluded by default (tagged with `:e2e`), require ChromeDriver

### Code Quality
- `mix precommit` - Run full precommit suite (auto-approved): compile with warnings as errors, unlock unused deps, check formatting, run Credo strict, run Sobelow security checks, and run tests. **Always run this when done with changes.**
- `mix compile` - Compile the project (auto-approved)
- `mix format` - Format code
- `mix credo --strict` - Run strict linting

### Assets
- `mix tailwind social_pomodoro` - Compile Tailwind CSS (auto-approved)
- `mix assets.build` - Build all assets (compile + Tailwind + esbuild)

## Architecture

### Core State Management

The application uses a **GenServer-based room architecture** with ETS-backed registries:

1. **Room (GenServer)** (`lib/social_pomodoro/room.ex`)
   - Each pomodoro room is an isolated GenServer process managing its own state
   - Handles timer ticks, participant management, session lifecycle, todos, status updates, and chat
   - State includes: participants, session_participants, spectators, timer, status (:autostart/:active/:break), todos, status_emoji, chat_messages, cycle tracking
   - Registered via Registry in `SocialPomodoro.RoomRegistry.Registry`
   - Self-terminates when all cycles complete or no participants remain after autostart

2. **RoomRegistry (GenServer + ETS)** (`lib/social_pomodoro/room_registry.ex`)
   - ETS table `:room_registry` maps room names → room PIDs
   - Provides room creation, lookup, and listing functionality
   - Filters empty rooms from listings (unless user is a session participant)

3. **UserRegistry (GenServer + ETS)** (`lib/social_pomodoro/user_registry.ex`)
   - ETS table `:user_registry` maps user_id → username
   - Allows username changes while maintaining persistent user identity
   - Broadcasts username updates via PubSub

4. **Timer** (`lib/social_pomodoro/timer.ex`)
   - Simple countdown timer struct with tick-based updates
   - States: :running, :stopped, :done
   - Used by Room for session and break timers

### Room State Machine

Rooms progress through three states:

1. **:autostart** - Countdown period (configurable via `SocialPomodoro.Config.autostart_countdown_seconds/0`, default 180s) before session begins
2. **:active** - Work session in progress (participants can join as spectators)
3. **:break** - Break period between cycles (spectators promoted to participants)

Key behaviors:
- **Spectators**: Users who join during `:active` state become spectators, promoted to participants during `:break`
- **Rejoining**: Session participants who disconnect can rejoin during `:active` or `:break` without becoming spectators
- **Multi-cycle support**: Rooms can run multiple work/break cycles (`total_cycles` and `current_cycle`)
- **Broadcast optimization**: Updates sent every 10 seconds during normal operation, or every second in final 10 seconds

### Real-Time Communication

Phoenix PubSub topics:
- `"rooms"` - Broadcasts room updates to lobby (all users watching lobby)
- `"room:#{name}"` - Broadcasts state updates to room participants
- `"user:#{user_id}"` - User-specific events (username updates, session start navigation)

### LiveView Structure

- **LobbyLive** (`lib/social_pomodoro_web/live/lobby_live.ex`) - Room creation and listing
- **SessionLive** (`lib/social_pomodoro_web/live/session_live.ex`) - Active session UI with three view modes:
  - `:spectator` - Read-only view during active session
  - `:active` - Work session interface with todos and status
  - `:break` - Break period with chat, completion message, and "go again" functionality

### Component Organization

Session-related components are split into focused modules:
- `SessionParticipantComponents` - Participant cards, avatar displays, collapsed previews
- `SessionTimerComponents` - Timer displays and countdowns
- `SessionTabsComponents` - Todo/chat tab switching

### Configuration

`SocialPomodoro.Config` centralizes all app settings:
- Duration options: [1, 25, 50, 75] minutes
- Cycle count options: [1, 2, 3, 4]
- Break duration options: [5, 10, 15] minutes
- Timer defaults for common durations (25min → 4 cycles, 50min → 2 cycles, etc.)
- Max todos per user: 5
- Autostart countdown: 180 seconds

### Session Features

- **Todos**: Users can add/toggle/delete up to 5 todos during active/break states
- **Status Emoji**: Users set emoji status (different sets for active vs break)
- **Chat**: Available during break only, max 3 messages per user (FIFO), 50 char limit
- **Go Again**: During break, users can vote to skip break - when all ready, next cycle starts immediately
- **Completion Messages**: Server-generated personalized messages at session end

### Telemetry

The application emits telemetry events for analytics:
- `[:pomodoro, :room, :created]`
- `[:pomodoro, :session, :started]` and `[:pomodoro, :session, :completed]`
- `[:pomodoro, :user, :connected]` - Fired **once per unique user** when first registered
- `[:pomodoro, :user, :rejoined]` and `[:pomodoro, :user, :set_working_on]`
- `[:pomodoro, :spectator, :joined]`, `[:pomodoro, :spectator, :left]`, `[:pomodoro, :spectator, :promoted]`
- `[:pomodoro, :cycle, :started]` and `[:pomodoro, :break, :skipped]`

Handled by `SocialPomodoro.TelemetryHandler` (can send to Discord webhook or other integrations).

**Visit Tracking**: The `[:pomodoro, :user, :connected]` event fires once per unique user when they are first registered in `UserRegistry`. This happens during the `UserSession` plug when a new user_id is assigned and their first username is generated. Subsequent username changes or reconnections do not trigger the event.

### User Session Management

- `UserSession` plug assigns `user_id` from session (creates if missing)
- `UsernameSession` plug redirects to username setup if needed
- User IDs persist across sessions via cookies

## UI Guidelines

### daisyUI 5 Integration

This project uses **daisyUI 5** with Tailwind CSS 4. Key points from `.github/instructions/daisyui.instructions.md`:

- daisyUI provides semantic component class names (btn, card, badge, etc.)
- Use daisyUI color names (`primary`, `base-100`, `error`, etc.) instead of Tailwind colors for theme compatibility
- Customize with Tailwind utilities when needed, use `!` suffix for specificity overrides as last resort
- No `tailwind.config.js` needed - v4 uses CSS imports: `@import "tailwindcss";` and `@plugin "daisyui";`
- Common components: btn, card, badge, avatar, modal, dropdown, toast, alert, etc.

### Phoenix/Elixir Guidelines (from AGENTS.md)

Key reminders:
- Phoenix 1.8+ wraps LiveView content with `<Layouts.app flash={@flash}>`
- Use `<.icon name="hero-x-mark">` for icons, never use Heroicons modules directly
- Use imported `<.input>` component for forms
- **Never** nest modules in same file (causes cyclic dependencies)
- **Never** use `if/else if` - use `cond` or `case` for multiple conditions
- HEEx class lists use `[...]` syntax: `class={["base", @flag && "conditional"]}`
- **Always** use `<%= for item <- @collection %>` for loops, never `Enum.each`
- LiveView streams require `phx-update="stream"` and consume `@streams.stream_name`
- Forms: assign with `to_form/2`, access with `@form[:field]`, never expose changesets in templates
- **Never** write inline `<script>` tags - use hooks in `assets/js/`

## Important Patterns

### Adding New Room Features

When adding features that modify room state:
1. Add client API function to `SocialPomodoro.Room` (e.g., `set_status/3`)
2. Implement `handle_call` in Room GenServer
3. Broadcast update with `broadcast_room_update/1`
4. Update `serialize_state/1` to include new state in client representation
5. Add LiveView event handler in `SessionLive`
6. Update templates to use new state

### Testing Strategy

- Unit tests for core logic (Timer, Room state transitions)
- LiveView tests using `Phoenix.LiveViewTest` and `LazyHTML`
- Integration tests for multi-user scenarios
- E2E tests with Wallaby (excluded by default, require ChromeDriver)
- Always add unique DOM IDs to elements for test selectors

### PubSub Patterns

- Subscribe in `mount/3` after `connected?(socket)` check
- Use specific topics for targeted updates (`"room:#{name}"` vs `"rooms"`)
- Clean up subscriptions in `terminate/2` callback
- Broadcast room state changes immediately after state updates

## Development Notes

- Tick interval is 1000ms (1 second) by default, configurable for testing
- Room process handles its own timer with `Process.send_after/3`
- State serialization enriches participant data with usernames, todos, status
- Completion messages generated server-side (not client-side) for consistency
- Wake Lock API integration via JS hooks to prevent screen sleep during sessions
