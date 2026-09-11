# Deployment

Load this file when working on CI/CD, Terraform, Dockerfiles, release scripts,
or environment configuration.

---

## Platform: DigitalOcean droplet (push-button-deploy)

Marquee deploys with the **push-button-deploy** process (`~/src/push-button-deploy`):
a single Ubuntu droplet running Docker Compose behind Caddy, provisioned by
Terraform roots that live in this repo under `infra/`.

| Concern | Implementation |
|---|---|
| Compute | One DO droplet running Docker Compose |
| TLS | Caddy, automatic Let's Encrypt issuance + renewal |
| Database | DO Managed Postgres, private VPC only, TLS `verify_peer` against the cluster CA |
| DNS | DNSimple A record pointing at a reserved IP that survives droplet recreation |
| Images | Built on GitHub amd64 runners, pushed to DO Container Registry, SHA-pinned |
| Deploys | Push to `main`: test → build → migrate (gated) → health-checked blue/green swap |
| Rollback | `gh workflow run rollback.yml -f tag=<previous sha>` — pins a prior image, no rebuild |
| Terraform state | Versioned DO Spaces bucket (S3-compatible backend) |
| Secrets | Never in cloud-init or droplet metadata — they arrive over SSH at deploy time |

Fly.io is gone: no `fly.toml`, no `flyctl` step, no `FLY_*` handling in
`rel/env.sh.eex`.

### Terraform roots (`infra/`)

```
infra/state/        the Spaces bucket holding the other roots' state (own state is local)
infra/persistent/   VPC, reserved IP, managed Postgres, DNSimple A record — prevent_destroy
infra/app/          droplet, reserved-IP assignment, firewall — disposable
```

Destroying `infra/app` never touches data: the DB firewall trusts a *tag* the
droplet wears, not the droplet itself. See `infra/README.md`.

Marquee is **Postgres-only**. Always run the bootstrap with
`DATABASE_BACKEND=postgres`; the tool's default is `sqlite`, which would ask
Terraform to tear the cluster down.

### Droplet layout

- `/root/caddy/` — the host-owned shared edge proxy (one per droplet), importing
  a site file per app.
- `/root/apps/marquee/` — this app's stack: its own compose project, volumes, and
  a `app_blue`/`app_green` pair publishing `marquee-blue` / `marquee-green`
  aliases on the shared `edge` network for Caddy to dial.

Port 22 is closed to the world. CI punches a temporary `/32` hole for its own
runner IP at the start of each deploy and revokes it in an `always()` step.

---

## Secrets Management

### Never commit secrets

Production secrets live in **GitHub Actions Secrets and Variables**. The deploy
workflow writes them into a mode-600 `.env` on the runner, ships it to the
droplet over SSH, and compose loads it. Nothing secret is in the image, in
cloud-init, or in droplet metadata.

An unset name interpolates to nothing, so `deploy.yml` strips `NAME=` lines
before shipping — `""` is truthy in Elixir and would otherwise configure Mux,
Stripe or Spaces with blank credentials instead of leaving them off.

### Required repo configuration

| Name | Kind | Purpose |
|---|---|---|
| `DIGITALOCEAN_ACCESS_TOKEN` | secret | registry + firewall ops |
| `SSH_PRIVATE_KEY` | secret | deploy key for the droplet |
| `DATABASE_URL` | secret | Postgres over the private VPC |
| `DATABASE_CA_CERT` | secret | cluster CA, shipped as `db-ca.pem` |
| `SECRET_KEY_BASE` | secret | Phoenix secret |
| `DOCR_REGISTRY` | var | DO Container Registry name |
| `DOMAIN` | var | public FQDN (matches the A record and cert) |
| `DROPLET_HOST` | var | reserved IP to SSH into |
| `FIREWALL_ID` | var | firewall to hole-punch |
| `APP_SLUG` | var | stack dir / compose project / Caddy site file / network aliases |

OpenTelemetry export to the hub is **required in prod** (both must be set, or
the release fails to boot — see below): var `OTEL_EXPORTER_OTLP_ENDPOINT` (the
hub base URL, e.g. `https://elixir-as-inf.diviningdad.com`; `/v1/traces` and
`/v1/logs` are appended) and secret `OTEL_HUB_TOKEN` (the per-source bearer
token, obtained once by registering "marquee" at the hub's `/sources/new` —
never commit it). They replace the former `OTEL_EXPORTER_OTLP_AUTH_HEADER`.

Marquee's own runtime configuration, all optional (an unset name disables that
integration): secrets `MUX_TOKEN_ID`, `MUX_TOKEN_SECRET`, `MUX_WEBHOOK_SECRET`,
`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_CONNECT_WEBHOOK_SECRET`,
`SPACES_ACCESS_KEY_ID`, `SPACES_SECRET_ACCESS_KEY`, `RESEND_API_KEY`,
`PEXELS_API_KEY`, `GRAFANA_LOKI_AUTH`; vars `POOL_SIZE`, `SPACES_BUCKET`,
`SPACES_REGION`, `SPACES_HOST`, `SPACES_PUBLIC_URL_BASE`, `MAILER_FROM`,
`GRAFANA_LOKI_URL`.

`PHX_SERVER`, `PHX_HOST`, `PORT` and `DATABASE_CA_FILE` are set by
`deploy/compose.yaml`, not by the `.env`.

### `config/runtime.exs` is the only place for prod config

The values the app cannot boot without — `DATABASE_URL`, `SECRET_KEY_BASE`, and
(via `Marquee.Otel.ExporterConfig`) `OTEL_EXPORTER_OTLP_ENDPOINT` and
`OTEL_HUB_TOKEN` — raise at boot when missing. The rest is guarded by
`if System.get_env(...)` so the feature switches off rather than half-configures.

### Database TLS is not optional

DO managed Postgres rejects non-TLS connections and Ecto does **not** infer TLS
from the URL. The block at the bottom of `config/runtime.exs` (marker:
`push-button-deploy: database TLS`) is appended last so Config merging makes it
the Repo's effective `:ssl`. With `DATABASE_CA_FILE` set (the deploy mounts
`db-ca.pem`) the server certificate is fully verified; without it the connection
is encrypted but unverified. Do not move that block above the Repo config.

---

## Release

### The Release module is required

`Marquee.Release.migrate/0` must exist and work. The deploy runs it as a one-off
container **before** traffic switches, so a failed migration leaves the old
release serving.

### Never use `mix` in production

Release commands only. `mix ecto.migrate` requires the Mix toolchain, which is
not present in a compiled release.

```shell
# ✅ CORRECT — release command, what deploy.yml runs
docker compose run --rm migrate bin/marquee eval 'Marquee.Release.migrate()'

# ❌ WRONG — requires Mix
mix ecto.migrate
```

### Clustering

There is no clustering on a single droplet: `DNS_CLUSTER_QUERY` is unset, so
`DNSCluster` starts with `:ignore`. `rel/env.sh.eex` names the node after the
container hostname, which is unique per color. Anything that assumed a cluster
(PubSub fan-out across nodes, cache invalidation across machines) now runs
in one node — revisit it before adding a second droplet.

### Health checks

Compose healthchecks the container by opening a TCP connection to the endpoint
on port 4000 and reading a status line — the slim runtime image has no curl or
wget. `GET /health` (`HealthController`) remains the app-level check.

---

## CI/CD: GitHub Actions

Two workflows, plus a manual rollback:

- **`ci.yml`** — the full quality gate on every push and PR: format check,
  `mix compile --warnings-as-errors`, `mix test --exclude e2e`, then a separate
  `e2e` job that provisions Chrome/chromedriver and runs `mix test --only e2e`.
- **`deploy.yml`** — push to `main`: `mix test --exclude e2e` (deploy's own
  red-tests-block-the-deploy gate) → build and push a SHA-pinned image to DOCR →
  ship `.env` and stack files over SSH → run migrations → blue/green swap.
  `workflow_dispatch` redeploys `main` without a commit, which is how a changed
  repo *variable* reaches the droplet.
- **`rollback.yml`** — `gh workflow run rollback.yml -f tag=<sha>` pins a prior
  image and re-swaps. No rebuild, no migration.

### Rules

- Deploy jobs declare `needs:` on the test job — deploys never run if tests fail
- Migrations run as a gated one-off container before the swap, never after
- One deploy at a time: the `concurrency` group queues rather than cancels, so
  an in-flight migration is never interrupted
- The runner's SSH hole is revoked in an `always()` step
- `deploy.yml`, `rollback.yml`, `Dockerfile`, `.dockerignore` and `deploy/*` are
  **copied unconditionally** by `bootstrap.sh`. They carry local modifications
  (see the header note in `deploy.yml`); re-apply them after any bootstrap
  re-run. Only `infra/` is seed-once.

### Day 2

| Want | Do |
|---|---|
| Deploy | `git push` to `main` |
| Watch a deploy | `gh run watch` |
| Roll back | `gh workflow run rollback.yml -f tag=<previous sha>` |
| Change infrastructure | edit `infra/…`, commit, `DATABASE_BACKEND=postgres ~/src/push-button-deploy/bootstrap.sh .` |
| Recreate the droplet | `terraform -chdir=infra/app destroy` then re-run the bootstrap — DB, IP, DNS, certs survive |
| SSH to the box | `ssh root@<reserved-ip>` (only from an IP in `SSH_CIDRS`) |

---

## Known gap: per-tenant domains

`deploy/site.caddy.tmpl` issues a certificate for **one** domain — the `DOMAIN`
repo variable. Tenant subdomains (`<slug>.<domain>`) and custom domains are not
covered. Serving them needs either a wildcard certificate (DNS-01 via the
DNSimple provider, which means a custom Caddy build) or Caddy on-demand TLS with
an `ask` endpoint that answers whether a hostname belongs to a live
organization. Neither exists yet; add the endpoint before pointing customer
domains at the droplet.

---

## What Not to Do in Deployment

- **No `mix` commands on the server** — use release commands only
- **No secrets in `config/config.exs` or `config/prod.exs`** — runtime only
- **No secrets in cloud-init, droplet metadata, or the image** — they arrive
  over SSH at deploy time
- **No deploys that skip tests** — the `needs:` gate is not optional
- **No migrations after the swap** — the gate runs before traffic moves
- **No `terraform.tfvars`** — tfvars outrank `TF_VAR_*` env and would silently
  override what the bootstrap passes in
- **No committed Terraform state** — `infra/.gitignore` covers state, backend
  pointers and real tfvars
- **No hardcoded hostnames** — `PHX_HOST` comes from the environment
- **No `DATABASE_BACKEND=sqlite`** — it would plan the managed cluster away
