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
      # Start the Finch HTTP client for sending emails
      {Finch, name: SocialPomodoro.Finch},
      # Start the room registry
      {Registry, keys: :unique, name: SocialPomodoro.RoomRegistry.Registry},
      SocialPomodoro.RoomRegistry,
      # Start to serve requests, typically the last entry
      SocialPomodoroWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SocialPomodoro.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SocialPomodoroWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
