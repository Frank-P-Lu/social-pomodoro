defmodule SocialPomodoro.Config do
  @moduledoc """
  Centralized configuration for application settings.
  Edit these values for local testing and development.
  """

  @doc """
  Minimum timer length in minutes (shown in lobby slider).
  """
  def min_timer_minutes, do: 1

  @spec autostart_countdown_seconds() :: 180
  @doc """
  Time before a room autostarts in seconds.
  """
  def autostart_countdown_seconds, do: 180
end
