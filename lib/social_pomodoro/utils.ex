defmodule SocialPomodoro.Utils do
  @moduledoc """
  General utility functions used across the application.
  """

  @doc """
  Returns true if the application is running in production environment.
  """
  def prod?() do
    Application.get_env(:social_pomodoro, :env) == :prod
  end
end
