defmodule SocialPomodoro.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SocialPomodoroWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:social_pomodoro, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SocialPomodoro.PubSub},
      # Start the user registry
      SocialPomodoro.UserRegistry,
      # Start the Finch HTTP client for sending emails
      {Finch, name: SocialPomodoro.Finch},
      # Start the room registry
      {Registry, keys: :unique, name: SocialPomodoro.RoomRegistry.Registry},
      SocialPomodoro.RoomRegistry,
      # Start to serve requests, typically the last entry
      SocialPomodoroWeb.Endpoint
    ]

    # Attach telemetry handlers for analytics
    attach_telemetry_handlers()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SocialPomodoro.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp attach_telemetry_handlers do
    :telemetry.attach(
      "pomodoro-room-created",
      [:pomodoro, :room, :created],
      &SocialPomodoro.TelemetryHandler.handle_event/4,
      nil
    )

    :telemetry.attach(
      "pomodoro-session-started",
      [:pomodoro, :session, :started],
      &SocialPomodoro.TelemetryHandler.handle_event/4,
      nil
    )

    :telemetry.attach(
      "pomodoro-session-completed",
      [:pomodoro, :session, :completed],
      &SocialPomodoro.TelemetryHandler.handle_event/4,
      nil
    )
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SocialPomodoroWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
