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
infra/state/        versioned Spaces bucket holding the other roots' state (own state is local)
infra/persistent/   DO project, VPC, reserved IP, managed Postgres (+ staging DB),
                    DNSimple A records (app, staging, tenants) — prevent_destroy
                    on the cluster, reserved IP and state bucket
infra/app/          droplet (Ubuntu 24.04, s-1vcpu-1gb), reserved-IP assignment,
                    firewall — disposable
```

Defaults worth knowing: region `nyc3`, Postgres 17 on `db-s-1vcpu-1gb` (one
node), DNS record `app` with TTL 300. `enable_staging` (default `true`) still
creates `<record>-stg.<zone>` and a `<project>-staging` database in the same
cluster, but nothing deploys to them now that the staging workflow is gone.
`tenant_slugs` creates one `<slug>-<record>.<zone>` A record per tenant.
The firewall opens 80/443 to the world and 22 only to `ssh_cidrs` (plus an
optional `gitea_runner_cidr`).

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

An unset secret or var interpolates to an empty string, and `deploy.yml` ships
those `KEY=` lines with an empty value — nothing strips them. `""` is truthy in
Elixir, so `runtime.exs` must treat `""` as unset for any setting it reads
(`MAILER_FROM`, `RESEND_API_KEY` and `SPACES_*` do; Mux and Stripe do not yet).

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
hub base URL, e.g. `https://elixir-as-inf.diviningdad.com`; `/v1/traces`,
`/v1/logs` and `/v1/metrics` are appended — see `.claude/observability.md`) and secret `OTEL_HUB_TOKEN` (the per-source bearer
token, obtained once by registering "marquee" at the hub's `/sources/new` —
never commit it). They replace the former `OTEL_EXPORTER_OTLP_AUTH_HEADER`.

Integration settings `deploy.yml` writes into the `.env`: secrets
`MUX_TOKEN_ID`, `MUX_TOKEN_SECRET`, `MUX_WEBHOOK_SECRET`, `STRIPE_SECRET_KEY`,
`STRIPE_WEBHOOK_SECRET`, `STRIPE_CONNECT_WEBHOOK_SECRET`, `RESEND_API_KEY`,
`PEXELS_API_KEY`, `SPACES_ACCESS_KEY_ID`, `SPACES_SECRET_ACCESS_KEY`; vars
`MAILER_FROM`, `SPACES_BUCKET`, `SPACES_REGION`, `SPACES_HOST`,
`SPACES_PUBLIC_URL_BASE` (empty Spaces vars fall back to the `marquee` bucket in
`nyc3`).

Tenant-hostname settings it also writes (see [Per-tenant hostnames](#per-tenant-hostnames)):
vars `ORG_RESOLUTION` (default `query_param`), `TENANT_HOST_PATTERN`,
`TENANT_DOMAIN_PROVISIONING` (default `false`), `DNSIMPLE_ACCOUNT_ID`,
`TENANT_DNS_ZONE`, `TENANT_DNS_TARGET_IPV4`, `TENANT_SLUGS` (edge only);
secret `DNSIMPLE_API_TOKEN`.

**Not shipped:** `runtime.exs` also reads `POOL_SIZE`, but no workflow writes
it, so the app's pool size is the default of 5.

`PHX_SERVER`, `PHX_HOST`, `PORT` and `DATABASE_CA_FILE` are set by
`deploy/compose.yaml`, not by the `.env`. The migration container runs with
`POOL_SIZE=2`.

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

Three workflows in `.github/workflows/`:

- **`ci.yml`** — every push to `main` and every PR against it. Three parallel
  jobs: `release` (prod deps, `mix compile --warnings-as-errors`,
  `mix assets.deploy`, `mix release`); `test` (asset type-check and coverage,
  `mix format --check-formatted`, warnings-as-errors compile,
  `mix coveralls --exclude e2e`); `e2e` (matching Chrome/ChromeDriver,
  `mix test --only e2e`, Wallaby screenshots uploaded as an artifact).
- **`deploy.yml`** — push to `main` or `workflow_dispatch`. `test`
  (`mix test --exclude e2e`, Elixir/OTP pins parsed from the `Dockerfile`) →
  `build` (amd64 image tagged with the commit SHA, pushed to DOCR) → `deploy`
  (hole-punch SSH, write `.env` + `db-ca.pem`, copy shared edge files to
  `/root/caddy` and stack files to `/root/apps/$APP_SLUG`, run `edge.sh`, pull,
  migrate, `swap.sh`, revoke SSH). It does **not** wait for `ci.yml`, so e2e
  failures do not block a deploy. `workflow_dispatch` redeploys `main` without a
  commit, which is how a changed repo *variable* reaches the droplet.
- **`rollback.yml`** — `gh workflow run rollback.yml -f tag=<sha>` verifies the
  tag exists in DOCR, rewrites `.env` with that image, and re-swaps. No rebuild,
  no migration. Shares the `deploy-<ref>` concurrency group with `deploy.yml`.
  Its `.env` must match `deploy.yml`'s apart from `IMAGE`;
  `test/marquee_web/deploy_env_parity_test.exs` enforces this, so add any new
  `.env` line to both workflows.

### Rules

- Deploy jobs declare `needs:` on the test job — deploys never run if tests fail
- Migrations run as a gated one-off container before the swap, never after
- One deploy at a time: the `concurrency` group queues rather than cancels, so
  an in-flight migration is never interrupted
- The runner's SSH hole is revoked in an `always()` step
- `deploy.yml`, `rollback.yml`, `Dockerfile`, `.dockerignore`
  and `deploy/*` are **copied unconditionally** by `bootstrap.sh` and carry
  Marquee-specific changes (the Mux/Stripe/OTEL/tenant `.env` lines, the tenant
  edge scripts, the removed `staging.yml`). Diff them after any bootstrap re-run
  and re-apply what it overwrote. Only `infra/` is seed-once.

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

## Per-tenant hostnames

The automatic path uses durable hostname allocations, DNSimple reconciliation,
and Caddy on-demand TLS. Existing-client migration applies an explicitly
reviewed snapshot; each tenant keeps its old URL until DNS and HTTPS are ready.
See [automatic tenant provisioning](../.docs/tenant-domain-provisioning.md) for
configuration, shared-edge prerequisites, release commands, and rollback. This
path does not require Terraform resources or deployments for each client.

The following explicit-list configuration is the manual alternative with
automatic provisioning disabled.

Tenant hostnames use `<slug>-<DOMAIN>`. `TENANT_SLUGS` supplies the explicit
comma-separated tenant list to the edge deployment; Terraform's `tenant_slugs`
set provisions the matching DNSimple A records. Caddy obtains normal automatic
HTTPS certificates for these explicit names. This does not require a wildcard
certificate, a custom Caddy build, or on-demand certificate issuance.

`ORG_RESOLUTION=hostname` enables host-based tenant URLs after DNS and TLS are
ready. It defaults to `query_param`. Runtime
`TENANT_HOST_PATTERN` defaults to `{slug}-<PHX_HOST>`; an alternate pattern needs
matching DNS and edge provisioning outside this convention. Deploy and rollback
must preserve the tenant list and runtime settings.

See [tenant hostname rollout](../.docs/tenant-hostnames.md) for configuration,
the staged rollout, authentication behavior, and rollback. Custom customer
domains are not automatically provisioned by this feature.

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
