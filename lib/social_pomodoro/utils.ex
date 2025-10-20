defmodule SocialPomodoro.Utils do
  @moduledoc """
  General utility functions used across the application.
  """

  @doc """
  Returns true if the application is running in production environment.
  """
  def prod? do
    Application.get_env(:social_pomodoro, :env) == :prod
  end

  @doc """
  Pluralizes a word based on a count.

  ## Examples

      iex> SocialPomodoro.Utils.pluralize(1, "person", "people")
      "person"

      iex> SocialPomodoro.Utils.pluralize(2, "person", "people")
      "people"

      iex> SocialPomodoro.Utils.pluralize(1, "spectator")
      "spectator"

      iex> SocialPomodoro.Utils.pluralize(3, "spectator")
      "spectators"
  """
  def pluralize(count, singular, plural \\ nil)
  def pluralize(1, singular, _plural), do: singular
  def pluralize(_count, _singular, plural) when plural != nil, do: plural
  def pluralize(_count, singular, nil), do: singular <> "s"

  @doc """
  Formats a count with its pluralized word.

  ## Examples

      iex> SocialPomodoro.Utils.count_with_word(1, "person", "people")
      "1 person"

      iex> SocialPomodoro.Utils.count_with_word(2, "person", "people")
      "2 people"

      iex> SocialPomodoro.Utils.count_with_word(1, "spectator")
      "1 spectator"

      iex> SocialPomodoro.Utils.count_with_word(3, "spectator")
      "3 spectators"
  """
  def count_with_word(count, singular, plural \\ nil) do
    "#{count} #{pluralize(count, singular, plural)}"
  end

  @doc """
  Formats "other people" for session completion messages.

  ## Examples

      iex> SocialPomodoro.Utils.other_people(1)
      "someone else"

      iex> SocialPomodoro.Utils.other_people(2)
      "2 other people"

      iex> SocialPomodoro.Utils.other_people(5)
      "5 other people"
  """
  def other_people(count) when count == 1, do: "someone else"
  def other_people(count), do: "#{count} other people"
end
