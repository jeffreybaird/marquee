defmodule Mix.Tasks.Marquee.SeedDemoOrgs do
  use Mix.Task

  @shortdoc "Seeds fully-populated demo organizations with Pexels video content via Mux."

  @moduledoc """
  Thin Mix wrapper around `Marquee.DemoSeeder.seed/1` for local development.

      mix marquee.seed_demo_orgs                        # all 5, skip existing
      mix marquee.seed_demo_orgs --force                # delete existing, recreate
      mix marquee.seed_demo_orgs --org wanderlust-tv    # single org
      mix marquee.seed_demo_orgs --org art-of-war-40k   # single org
      mix marquee.seed_demo_orgs --org prism-plus       # single org

  Requires `PEXELS_API_KEY` env var. Mux credentials must be configured. In
  production (no Mix), run `Marquee.Release.seed_demo/1` instead.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean, org: :string])

    Marquee.DemoSeeder.seed(force: opts[:force] || false, org: opts[:org])
  end
end
