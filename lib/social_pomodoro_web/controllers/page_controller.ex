defmodule SocialPomodoroWeb.PageController do
  use SocialPomodoroWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
