defmodule SocialPomodoroWeb.UsernameController do
  use SocialPomodoroWeb, :controller

  def update(conn, %{"username" => username}) do
    conn
    |> put_session(:username, username)
    |> put_resp_cookie("_social_pomodoro_username", username,
      max_age: 60 * 60 * 24 * 365,
      http_only: true
    )
    |> put_flash(:info, "Username updated!")
    |> redirect(to: ~p"/")
  end
end
