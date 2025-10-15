ExUnit.start()

# Start Wallaby for e2e tests (optional - only needed when running e2e tests)
case Application.ensure_all_started(:wallaby) do
  {:ok, _} ->
    :ok

  {:error, _} ->
    IO.puts("Wallaby not started (ChromeDriver not found). E2E tests will be skipped.")
end

# Exclude e2e tests from regular test runs
ExUnit.configure(exclude: [:e2e])
