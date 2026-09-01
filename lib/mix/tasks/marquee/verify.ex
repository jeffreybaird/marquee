defmodule Mix.Tasks.Marquee.Verify do
  use Mix.Task

  @shortdoc "Runs format, credo, dialyzer, unit tests, then e2e; stops on first failure."

  @moduledoc """
  Runs the local verification suite in order:

  1. `mix format`
  2. `mix credo --strict`
  3. `mix dialyzer`
  4. `mix test`
  5. `mix test --only e2e`

  Stops at the first failing step. Raises or exits the same way the underlying
  Mix tasks do, so the shell exit code reflects failure.
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("format", [])
    Mix.Task.run("credo", ["--strict"])
    Mix.Task.run("dialyzer", [])
    Mix.Task.run("test", ["--only", "e2e"])
    Mix.Task.run("test", [])
  end
end
