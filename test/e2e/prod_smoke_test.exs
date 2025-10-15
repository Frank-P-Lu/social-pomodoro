defmodule SocialPomodoroWeb.E2E.ProdSmokeTest do
  use ExUnit.Case, async: false
  use Wallaby.Feature

  @moduletag :e2e

  # Get the target URL from environment variable, defaults to production
  @target_url System.get_env("E2E_TARGET_URL", "https://www.focuswithstrangers.com")

  feature "homepage loads and displays welcome message", %{session: session} do
    session
    |> visit(@target_url)
    |> assert_has(Query.text("Fancy a Pomodoro?"))
  end
end
