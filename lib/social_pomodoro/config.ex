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
  def break_duration_options, do: [5, 10, 15]

  @doc """
  Default pomodoro duration in minutes.
  """
  def default_pomodoro_duration, do: 25

  @doc """
  Default number of cycles.
  """
  def default_cycle_count, do: 4

  @doc """
  Default break duration in minutes.
  """
  def default_break_duration, do: 5

  @doc """
  Default configuration for each supported pomodoro duration.

  Returns a map keyed by duration in minutes, with values containing
  the default number of cycles and break duration in minutes.
  """
  def timer_defaults do
    %{
      25 => %{cycles: 4, break_minutes: 5},
      50 => %{cycles: 2, break_minutes: 10},
      75 => %{cycles: 1, break_minutes: 5}
    }
  end

  @doc """
  Returns the default cycle and break configuration for a given duration.
  """
  def defaults_for_duration(duration_minutes) do
    Map.get(timer_defaults(), duration_minutes, %{
      cycles: default_cycle_count(),
      break_minutes: default_break_duration()
    })
  end

  @doc """
  Break duration to enforce when only a single pomodoro is scheduled.
  """
  def single_cycle_break_duration, do: 5

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
