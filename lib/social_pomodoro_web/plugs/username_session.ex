defmodule SocialPomodoroWeb.Plugs.UsernameSession do
  @moduledoc """
  Reads username from cookie and puts it into session for LiveView access.
  """
  import Plug.Conn

  @cookie_key "_social_pomodoro_username"
  # 1 year
  @max_age 60 * 60 * 24 * 365

  def init(_opts), do: %{}

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    # Priority: session (user just updated) > cookie > generate new
    session_username = get_session(conn, :username)
    cookie_username = conn.cookies[@cookie_key]

    username = session_username || cookie_username || generate_friendly_username()

    # Always sync cookie with current username (handles updates from LiveView)
    conn
    # Makes it available in LiveView mount/3
    |> put_session(:username, username)
    # Makes it available in controllers
    |> assign(:username, username)
    |> put_resp_cookie(@cookie_key, username, max_age: @max_age, http_only: true)
  end

  defp generate_friendly_username do
    adjectives = [
      "Happy",
      "Focused",
      "Calm",
      "Bright",
      "Swift",
      "Quiet",
      "Bold",
      "Clever",
      "Gentle",
      "Brave"
    ]

    nouns = [
      "Panda",
      "Tiger",
      "Eagle",
      "Dolphin",
      "Phoenix",
      "Dragon",
      "Wolf",
      "Fox",
      "Bear",
      "Lion"
    ]

    adj = Enum.random(adjectives)
    noun = Enum.random(nouns)

    "#{adj}#{noun}#{:rand.uniform(99)}"
  end
end
