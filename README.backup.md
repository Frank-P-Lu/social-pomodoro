# SocialPomodoro

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Features

### Feedback Component

Users can submit feedback directly from the app using the "Give Feedback" button on the home page. The feedback is sent to a Discord webhook.

To configure Discord webhook for feedback:

1. Set the `DISCORD_WEBHOOK_URL` environment variable with your Discord webhook URL
2. See `lib/social_pomodoro/discord/README.md` for detailed setup instructions

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
