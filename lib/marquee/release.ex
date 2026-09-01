defmodule Marquee.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :marquee

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Seeds the content-rich demo organizations from a running release (no Mix).

  Boots the full application (Repo, PubSub, Req, Mux client) — `migrate/0`'s
  `with_repo` starts only the Repo, which is not enough for the seeder's
  Pexels/Mux calls — then delegates to `Marquee.DemoSeeder.seed/1`. Accepts the
  same options: `:pexels_key` (falls back to the `PEXELS_API_KEY` env var),
  `:org` (single slug), `:force` (recreate existing).

  Run on the droplet's migrate runner:

      docker compose --profile tools run --rm migrate \\
        bin/marquee eval 'Marquee.Release.seed_demo([])'
  """
  def seed_demo(opts \\ []) do
    start_app()
    Marquee.DemoSeeder.seed(opts)
  end

  @doc """
  Reconciles pending Mux assets against Mux's current state from a running
  release (no Mix). Boots the full app, then delegates to
  `Marquee.Content.reconcile_pending_mux_assets/1`.

  Use after a bulk seed or a domain move, when assets finished processing while
  no webhook endpoint was reachable, to flip them `preparing` -> `ready`.

      docker compose --profile tools run --rm migrate \\
        bin/marquee eval 'Marquee.Release.reconcile_mux()'
  """
  def reconcile_mux(opts \\ []) do
    start_app()
    Marquee.Content.reconcile_pending_mux_assets(opts)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end

  defp start_app do
    Application.ensure_all_started(:ssl)
    {:ok, _} = Application.ensure_all_started(@app)
    :ok
  end
end
