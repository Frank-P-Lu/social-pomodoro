# Telemetry Analytics

This document describes the telemetry analytics implementation for Social Pomodoro.

## Overview

The application emits telemetry events for key user actions and sends them to a Discord webhook for analytics tracking. This allows monitoring of room creation, session starts, and session completions.

## Configuration

The Discord webhook URL is configured via the `DISCORD_FEEDBACK_WEBHOOK_URL` environment variable (same as the feedback webhook).

```bash
export DISCORD_FEEDBACK_WEBHOOK_URL="https://discord.com/api/webhooks/..."
```

## Telemetry Events

### 1. Room Created
**Event:** `[:pomodoro, :room, :created]`

**Emitted when:** A new room is created

**Metadata:**
- `room_id` - The unique room identifier
- `user_id` - The creator's user ID (not username)
- `duration_minutes` - The session duration in minutes

**Location:** `lib/social_pomodoro/room_registry.ex`

### 2. Session Started
**Event:** `[:pomodoro, :session, :started]`

**Emitted when:** A pomodoro session is started

**Metadata:**
- `room_id` - The room identifier
- `user_id` - The starter's user ID (typically the room creator)
- `participant_count` - Number of participants in the session
- `wait_time_seconds` - Time elapsed between room creation and session start

**Location:** `lib/social_pomodoro/room.ex` (in `handle_call(:start_session)` and `handle_call({:go_again, _})`)

**Note:** When a session is restarted after a break using "go again", the `wait_time_seconds` is 0.

### 3. Session Completed
**Event:** `[:pomodoro, :session, :completed]`

**Emitted when:** A pomodoro session timer completes (reaches 0)

**Metadata:**
- `room_id` - The room identifier
- `participant_count` - Number of participants who completed the session
- `duration_minutes` - The session duration in minutes

**Location:** `lib/social_pomodoro/room.ex` (in `handle_info(:tick, %{seconds_remaining: 0, status: :active})`)

## Handler Implementation

The `SocialPomodoro.TelemetryHandler` module handles all telemetry events and sends them to Discord.

**File:** `lib/social_pomodoro/telemetry_handler.ex`

The handler:
1. Receives telemetry events
2. Formats the event data for Discord
3. Sends the data to the configured webhook
4. Logs errors if the webhook fails (but doesn't crash the application)

## Testing

Tests for the telemetry handler are located in `test/social_pomodoro/telemetry_handler_test.exs`.

## Privacy

All telemetry events use **user IDs** (UUIDs) instead of usernames to protect user privacy while still allowing analytics tracking.
