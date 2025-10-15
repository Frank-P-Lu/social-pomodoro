defmodule SocialPomodoro.BotPersonality do
  @moduledoc """
  Defines bot personalities with their unique characteristics.
  Each bot has a distinct username, avatar, and set of messages/emojis.
  """

  defstruct [:user_id, :username, :messages, :emojis, :avatar]

  @type t :: %__MODULE__{
          user_id: String.t(),
          username: String.t(),
          messages: [String.t()],
          emojis: [String.t()],
          avatar: String.t()
        }

  @doc """
  Returns all available bot personalities.
  """
  @spec all() :: [t()]
  def all do
    [
      %__MODULE__{
      user_id: "bot_alice",
      username: "Alice (bot)",
      messages: [
        "Great work everyone!",
        "Keep it up!",
        "Nice focus session!",
        "You all did amazing!",
        "Productive session!"
      ],
      emojis: ["1F44D", "1F389", "2728", "1F31F"],
      avatar: "alice.svg"
    },
    %__MODULE__{
      user_id: "bot_bob",
      username: "Bob (bot)",
      messages: [
        "You got this!",
        "Awesome session!",
        "Well done team!",
        "Crushing it!",
        "Keep up the momentum!"
      ],
      emojis: ["1F525", "1F4AA", "1F680", "26A1"],
      avatar: "bob.svg"
    },
    %__MODULE__{
      user_id: "bot_charlie",
      username: "Charlie (bot)",
      messages: [
        "Feeling energized!",
        "That was intense!",
        "Ready for the next one!",
        "Great vibes here!",
        "Love the focus!"
      ],
      emojis: ["1F60E", "1F929", "1F973", "1F4AF"],
      avatar: "charlie.svg"
    }
    ]
  end

  @doc """
  Returns a random bot personality.
  """
  @spec random() :: t()
  def random do
    Enum.random(all())
  end

  @doc """
  Gets a random message from a bot personality.
  """
  @spec random_message(t()) :: String.t()
  def random_message(%__MODULE__{messages: messages}) do
    Enum.random(messages)
  end

  @doc """
  Gets a random emoji from a bot personality.
  """
  @spec random_emoji(t()) :: String.t()
  def random_emoji(%__MODULE__{emojis: emojis}) do
    Enum.random(emojis)
  end

  @doc """
  Checks if a user_id belongs to a bot.
  """
  @spec bot?(String.t()) :: boolean()
  def bot?(user_id) do
    String.starts_with?(user_id, "bot_")
  end
end
