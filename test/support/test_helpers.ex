defmodule SocialPomodoro.TestHelpers do
  @moduledoc """
  Helper functions and constants for tests.
  """

  # Sleep duration constant for tests (in milliseconds)
  @sleep_short 1

  def sleep_short, do: Process.sleep(@sleep_short)
end
