# Deployment

Load this file when working on CI/CD, Fly.io configuration, Dockerfiles,
release scripts, or environment configuration.

---

## Platform: Fly.io

Bobine deploys to Fly.io. Configuration lives in `fly.toml` at the project
root.

### Why Fly.io

- Native Elixir clustering via DNS-based node discovery (`dns_cluster`)
- Per-second billing on compute
- Multi-region deployment with a single command
- Managed Postgres with automatic failover
- LiveView WebSocket connections benefit from low-latency edge routing

---

## Secrets Management

### Never commit secrets

All production secrets live in Fly secrets (`fly secrets set KEY=VALUE`) and in
GitHub Actions Secrets. They must never appear in source code, `config/` files,
or be logged.

### Required environment variables

| Variable                | Set In         | Purpose                          |
|-------------------------|----------------|----------------------------------|
| `DATABASE_URL`          | Fly (auto)     | Postgres connection string       |
| `SECRET_KEY_BASE`       | Fly + GH       | Phoenix secret key               |
| `PHX_HOST`              | Fly + GH       | Primary hostname                 |
| `MUX_TOKEN_ID`          | Fly + GH       | Mux API credential               |
| `MUX_TOKEN_SECRET`      | Fly + GH       | Mux API credential               |
| `MUX_WEBHOOK_SECRET`    | Fly            | Mux webhook signing secret       |
| `STRIPE_SECRET_KEY`     | Fly + GH       | Stripe API key                   |
| `STRIPE_WEBHOOK_SECRET` | Fly            | Stripe webhook signing secret    |
| `RELEASE_COOKIE`        | Fly            | Erlang distribution cookie       |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Fly     | OpenTelemetry OTLP endpoint (optional) |

### `config/runtime.exs` is the only place for prod config

All production configuration reads from `System.fetch_env!/1`. Use
`System.fetch_env!` (bang) not `System.get_env` so missing vars fail loudly
at boot rather than silently misbehaving.

```elixir
# ✅ CORRECT — fails loudly if missing
config :stream_vane, :mux_token_id, System.fetch_env!("MUX_TOKEN_ID")

# ❌ WRONG — silently nil if missing
config :stream_vane, :mux_token_id, System.get_env("MUX_TOKEN_ID")
```

---

## Release

### The Release module is required

`Bobine.Release.migrate/0` must exist and work correctly. It is called by
the Fly deployment process before the service starts.

```elixir
defmodule Bobine.Release do
  @app :stream_vane

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

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
  defp load_app, do: Application.ensure_all_started(:ssl)
end
```

### Never use `mix` in production

Release commands only. `mix ecto.migrate` requires the Mix toolchain which is
not present in a compiled release.

```shell
# ✅ CORRECT — release command
/app/bin/stream_vane eval "Bobine.Release.migrate()"

# ❌ WRONG — requires Mix
mix ecto.migrate
```

---

## Fly.io Configuration

### `fly.toml` essentials

```toml
[env]
  PHX_HOST = "Bobine.com"
  ECTO_IPV6 = "true"
  ERL_AFLAGS = "-proto_dist inet6_tcp"
  DNS_CLUSTER_QUERY = "Bobine.internal"
  RELEASE_DISTRIBUTION = "name"

[deploy]
  release_command = "/app/bin/stream_vane eval Bobine.Release.migrate"
```

### Clustering

Erlang clustering is configured via `dns_cluster` in the application supervision
tree. Fly's internal DNS resolves `<app-name>.internal` to all running instances.

```elixir
# In application.ex
children = [
  {DNSCluster, query: Application.get_env(:stream_vane, :dns_cluster_query) || :ignore},
  {Phoenix.PubSub, name: Bobine.PubSub},
  # ...
]
```

### Health checks

Fly health checks should hit a lightweight endpoint that confirms the app is
running and the database is reachable. Do not use a LiveView route for health
checks.

```elixir
# A simple plug-based health check
get "/health", HealthController, :check
```

---

## CI/CD: GitHub Actions

### Workflow structure

```yaml
# .github/workflows/deploy.yml
name: CI & Deploy

on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        # ...
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix format --check-formatted
      - run: mix credo --strict
      - run: mix dialyzer
      - run: npx tsc --noEmit --project assets/tsconfig.json
      - run: mix test
      - run: mix assets.deploy

  deploy:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - run: flyctl deploy --remote-only
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

### Rules

- The `deploy` job must declare `needs: test` — deploys never run if tests fail
- `mix compile --warnings-as-errors` treats warnings as failures
- `mix credo --strict` enforces code quality
- `npx tsc --noEmit` type-checks TypeScript hooks without emitting files
- `mix assets.deploy` compiles assets in CI, not on the server
- Migrations run via the `release_command` in `fly.toml`, before the new
  version starts serving traffic
- The `--remote-only` flag on `flyctl deploy` uses Fly's remote builder,
  avoiding architecture mismatches (especially on Apple Silicon)

---

## What Not to Do in Deployment

- **No `mix` commands on the server** — use release commands only
- **No secrets in `config/config.exs` or `config/prod.exs`** — runtime only
- **No deploys that skip tests** — the `needs: test` gate is not optional
- **No direct pushes that bypass the workflow** — always push to `main` and
  let the workflow run
- **No hardcoded hostnames** — `PHX_HOST` comes from the environment
- **No ignoring IPv6 settings** — Fly's internal network is IPv6, the
  `ECTO_IPV6` and `ERL_AFLAGS` settings are not optional
