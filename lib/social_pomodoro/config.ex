defmodule SocialPomodoro.Config do
  @moduledoc """
  Centralized configuration for application settings.
  Edit these values for local testing and development.
  """

  @doc """
  Available pomodoro duration options in minutes.
  """
  def pomodoro_duration_options, do: [1, 25, 50, 75]

  @doc """
  Available cycle count options.
  """
  def cycle_count_options, do: [1, 2, 3, 4]

  @doc """
  Available break duration options in minutes.
  """
  def break_duration_options, do: [1, 5, 10, 15]

  @doc """
  Default pomodoro duration in minutes.
  """
  def default_pomodoro_duration, do: 25

  @doc """
  Default number of cycles.
  """
  def default_cycle_count, do: 1

  @doc """
  Default break duration in minutes.
  """
  def default_break_duration, do: 5

  @spec autostart_countdown_seconds() :: 180
  @doc """
  Time before a room autostarts in seconds.
  """
  def autostart_countdown_seconds, do: 180

  @doc """
  Maximum number of todos per user.
  """
  def max_todos_per_user, do: 5
end
