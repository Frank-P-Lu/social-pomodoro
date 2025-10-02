defmodule SocialPomodoroWeb.Plugs.UserSession do
  @moduledoc """
  Manages persistent user identity with user_id and maps to usernames via UserRegistry.
  """
  import Plug.Conn

  @cookie_key "_social_pomodoro_user_id"
  # 1 year
  @max_age 60 * 60 * 24 * 365

  def init(_opts), do: %{}

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    # Get or generate user_id
    user_id = get_session(conn, :user_id) || conn.cookies[@cookie_key] || generate_user_id()

    # Ensure user has a username in the registry
    username = SocialPomodoro.UserRegistry.get_username(user_id)

    if is_nil(username) do
      # Generate friendly username for new users
      new_username = generate_friendly_username()
      SocialPomodoro.UserRegistry.set_username(user_id, new_username)
    end

    # Store user_id in session and cookie
    conn
    |> put_session(:user_id, user_id)
    |> assign(:user_id, user_id)
    |> put_resp_cookie(@cookie_key, user_id, max_age: @max_age, http_only: true)
  end

  defp generate_user_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
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
