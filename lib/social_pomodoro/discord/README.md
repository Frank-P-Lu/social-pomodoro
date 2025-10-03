# Discord Webhook Configuration

This directory contains the Discord integration for sending feedback messages to Discord via webhooks.

## Setup

To enable Discord feedback notifications:

1. Create a webhook in your Discord server:
   - Go to Server Settings → Integrations → Webhooks
   - Click "New Webhook"
   - Choose the channel where you want feedback to appear
   - Copy the webhook URL

2. Set the environment variable:
   ```bash
   export DISCORD_FEEDBACK_WEBHOOK_URL="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"
   ```

   For development, add this to your `.env` file (copy from `.env.example`):
   ```
   DISCORD_FEEDBACK_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK_URL
   ```

3. The webhook is configured in `config/runtime.exs` to read from the `DISCORD_FEEDBACK_WEBHOOK_URL` environment variable.

## Usage

The `SocialPomodoro.Discord.Webhook` module provides a simple interface:

```elixir
# Send feedback with email
Webhook.send_feedback("This is great!", "user@example.com")

# Send feedback without email
Webhook.send_feedback("This is great!")
```

## Behavior

- If the webhook URL is not configured, feedback submissions will still work but won't send to Discord
- Users will see a success message regardless
- All webhook activity is logged for debugging purposes
