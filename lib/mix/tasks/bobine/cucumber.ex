defmodule Mix.Tasks.Bobine.Cucumber do
  @shortdoc "Run Cucumber BDD acceptance tests (no HTTP server)"
  @moduledoc """
  Runs cucumberex against features/acceptance/ with the HTTP endpoint disabled.
  Intended for context-level BDD tests that don't require a browser.

  ## Usage

      MIX_ENV=test mix bobine.cucumber [options] [feature_files]

  All cucumberex options are forwarded as-is. Defaults to features/acceptance/.

  ## Examples

      MIX_ENV=test mix bobine.cucumber
      MIX_ENV=test mix bobine.cucumber features/acceptance/authentication.feature
      MIX_ENV=test mix bobine.cucumber --tags @smoke
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Application.put_env(:bobine, BobineWeb.Endpoint, server: false)
    args = if args == [], do: ["features/acceptance"], else: args
    Mix.Task.run("cucumber", args)
  end
end
