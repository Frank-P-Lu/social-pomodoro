defmodule SocialPomodoro.RoomNameGenerator do
  @moduledoc """
  Generates random, peaceful room names for pomodoro sessions.
  """

  @adjectives [
    "Hushed",
    "Steady",
    "Mellow",
    "Quiet",
    "Focused",
    "Ambient",
    "Calm",
    "Clear",
    "Deep",
    "Gentle",
    "Bright",
    "Zen",
    "Vast",
    "Warm",
    "Crisp"
  ]

  @nouns_a [
    "Library",
    "Mountain",
    "Garden",
    "Coffee",
    "Forest",
    "Starlight",
    "River",
    "Marble",
    "Studio",
    "Teahouse",
    "Harbor",
    "Cloud",
    "Oak",
    "Desert",
    "Echo"
  ]

  @nouns_b [
    "Corner",
    "Cabin",
    "Bench",
    "Shop",
    "Grove",
    "Gaze",
    "Flow",
    "Counter",
    "Loft",
    "Nook",
    "View",
    "Ceiling",
    "Desk",
    "Silence",
    "Breeze"
  ]

  @doc """
  Generates a random room name by combining an adjective, noun A, and noun B with hyphens.

  ## Examples

      iex> SocialPomodoro.RoomNameGenerator.generate()
      "Hushed-Coffee-Corner"

  """
  def generate do
    adjective = Enum.random(@adjectives)
    noun_a = Enum.random(@nouns_a)
    noun_b = Enum.random(@nouns_b)

    "#{adjective}-#{noun_a}-#{noun_b}"
  end
end
