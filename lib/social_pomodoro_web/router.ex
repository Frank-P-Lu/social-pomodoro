defmodule SocialPomodoroWeb.Router do
  use SocialPomodoroWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SocialPomodoroWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug SocialPomodoroWeb.Plugs.UserSession
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SocialPomodoroWeb do
    pipe_through :browser

    live "/", LobbyLive
    live "/at/:room_name", LobbyLive
    live "/room/:name", SessionLive
  end

  # Other scopes may use custom stacks.
  scope "/api", SocialPomodoroWeb do
    pipe_through :browser

    post "/feedback", FeedbackController, :create
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:social_pomodoro, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SocialPomodoroWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
