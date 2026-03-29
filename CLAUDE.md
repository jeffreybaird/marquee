# CLAUDE.md — Bobine

This file is read automatically by Claude Code on every session. Follow all rules
here without exception unless the user explicitly overrides one for a specific task.

Additional context-specific rules live in `.claude/`. Load the relevant file(s)
when working in a specific domain:

- `.claude/multi-tenancy.md` — tenant scoping, query patterns, test isolation
- `.claude/mux-integration.md` — Mux client, webhooks, asset conventions
- `.claude/stripe-integration.md` — Stripe client, subscriptions, webhooks
- `.claude/deployment.md` — Fly.io, CI/CD, secrets, releases
- `.claude/rbac.md` — roles, enforcement, plugs
- `.claude/branding-and-theming.md` — CSS variables, templates, per-tenant styling
- `.claude/typescript-hooks.md` — hook conventions, file structure, events
- `.claude/testing.md` — Mox setup, factories, DataCase helpers, integration tests
- `.claude/architecture-decisions.md` — audit logging, soft deletes, pagination, events, error shapes, feature flags
- `.claude/observability.md` Instrumentation and logging

---

## Project Overview

A multi-tenant SaaS OTT (Over-The-Top) video platform built with Elixir / Phoenix
LiveView. Businesses (tenants) use the operator dashboard to manage video content,
configure their branded viewer-facing site, and monetize via subscriptions. Video
infrastructure is powered by Mux. Billing is powered by Stripe.

### Architecture Summary

- **Multi-tenant:** Shared Postgres schema with `organization_id` on every
  tenant-scoped table. Tenant resolved from subdomain or custom domain.
- **Two interfaces:**
  - Operator dashboard (`/admin/*`) — content management, analytics, branding,
    RBAC, webhooks. Built entirely in LiveView.
  - Viewer-facing site — templated per-tenant, subscription-gated, video playback
    via Mux Player. LiveView with TypeScript hooks for player integration.
- **Video:** Mux Elixir SDK for encoding, storage, delivery, and analytics.
  We never serve video bytes — Mux handles all CDN delivery.
- **Billing:** Stripe for SVOD subscriptions. Built with the understanding that
  AVOD, TVOD, and hybrid models will be added later.
- **Background jobs:** Oban for webhook delivery, analytics aggregation, Mux
  webhook processing, and Stripe subscription sync.
- **Deployment:** Fly.io with GitHub Actions CI/CD.

### Context Modules

All business logic lives in these context modules. LiveViews and controllers never
call `Repo` directly.

| Context          | Responsibility                                        |
|------------------|-------------------------------------------------------|
| `Accounts`       | Users, organizations, memberships, invitations, RBAC  |
| `Content`        | Videos, collections, tags, Mux client wrapper         |
| `Catalog`        | Homepage rows, row items, layout config               |
| `Engagement`     | Watchlists, favorites, watch history, playback progress |
| `Billing`        | Stripe subscriptions, plans, checkout                 |
| `Analytics`      | Raw events, aggregations, real-time stats             |
| `Notifications`  | Push notifications, notification records, delivery    |
| `Branding`       | Per-org themes, template selection                    |
| `Webhooks`       | Outbound webhook endpoints, events, delivery          |

---

## Code Style Rules

## **NOTE: EVERY ADDITIONAL CODE WRITTEN THAT ADDS BEHAVIOR MUST BE ACCOMPANIED BY A TEST THAT VALIDATES SAID BEHAVIOR**

## Run `mix format` on every change

### 1. Single Responsibility — One Function, One Job

Every function does exactly one thing. If you find yourself writing `and` in a
`@doc` description, the function needs to be split.

```elixir
# ✅ CORRECT — each step is its own function
def create_video_from_mux_asset(organization, mux_asset_attrs) do
  mux_asset_attrs
  |> normalize_mux_metadata()
  |> build_video_changeset(organization)
  |> Repo.insert()
end

# ❌ WRONG — Mux API call and database insert mixed together
def create_video(organization, upload_params) do
  {:ok, asset} = MuxClient.create_asset(upload_params)
  Repo.insert(%Video{title: asset.title, mux_asset_id: asset.id, ...})
end
```

### 2. Pipe-First Data Transformation

All multi-step data transformations use `|>`. The input data flows top to bottom.
Avoid intermediate variables when a pipe expresses intent more clearly.

```elixir
# ✅ CORRECT
def build_theme_css(theme) do
  theme
  |> extract_css_variables()
  |> merge_with_template_defaults()
  |> render_css_string()
end

# ❌ WRONG — named intermediates obscure the flow
def build_theme_css(theme) do
  vars = extract_css_variables(theme)
  merged = merge_with_template_defaults(vars)
  render_css_string(merged)
end
```

Acceptable exceptions: when a value is used more than once, or when naming it
genuinely improves readability (e.g. a complex pattern match result).

### 3. Doctests on Every Public Function

Every public function (`def`, not `defp`) must have a `@doc` block with at least one
doctest demonstrating the happy path. The doctest must be runnable — use real values,
not placeholders.

```elixir
@doc """
Derives the subdomain from an organization's slug.

    iex> Bobine.Accounts.subdomain_for(%Bobine.Accounts.Organization{slug: "acme-films"})
    "acme-films.Bobine.com"
"""
def subdomain_for(%Organization{slug: slug}) do
  "#{slug}.Bobine.com"
end
```

Rules for doctests:
- Use `iex>` format, not prose descriptions of what the function returns
- Cover the happy path only — edge cases belong in unit tests
- The doctests should always exercise the most intended pathway — for example if
  there is a collection being processed, the test should not have an empty
  collection as the test data.
- If the function returns a struct or large map, test a specific field:
  `iex> result.mux_asset_id` rather than the whole struct
- Doctests for functions that hit the database are **exempt** — use unit tests instead
- Doctests for functions that call external services (Mux, Stripe) are **exempt** —
  use unit tests with mocks instead

### 4. Error Handling with `{:ok, _} / {:error, _}`

All functions that can fail return tagged tuples. Never raise from a public
context function — let the caller decide how to handle errors.

```elixir
# ✅ CORRECT
def create_subscription(organization, user, plan) do
  with {:ok, stripe_sub} <- StripeClient.create_subscription(user, plan),
       {:ok, sub}         <- persist_subscription(organization, user, stripe_sub) do
    {:ok, sub}
  else
    {:error, reason} -> {:error, reason}
  end
end

# ❌ WRONG — raises on Stripe failure
def create_subscription(organization, user, plan) do
  stripe_sub = StripeClient.create_subscription!(user, plan)
  persist_subscription!(organization, user, stripe_sub)
end
```

Exception: `get_video!/2` and similar bang functions are acceptable for cases
where a missing record is a programmer error (e.g. following a valid FK), not user
input.

### 5. Private Functions Are Prefixed with Intent

Name private helpers to describe what they do to the data, not what they are:

```elixir
defp reject_expired_subscriptions(subs)  # ✅
defp filter_subs(subs)                   # ❌ — filter to what?

defp normalize_mux_webhook_payload(map)  # ✅
defp process_webhook(map)                # ❌ — process how?
```

### 6. Contexts Are the Public API

All database access goes through context modules. LiveViews and controllers never
call `Repo` directly.

```elixir
# ✅ CORRECT — LiveView delegates to context
def handle_event("add_to_watchlist", %{"video_id" => video_id}, socket) do
  org = socket.assigns.organization
  user = socket.assigns.current_user
  {:ok, _} = Engagement.add_to_watchlist(org, user, video_id)
  {:noreply, assign(socket, watchlist: Engagement.list_watchlist(org, user))}
end

# ❌ WRONG — LiveView queries directly
def handle_event("add_to_watchlist", %{"video_id" => video_id}, socket) do
  Repo.insert(%WatchlistItem{user_id: socket.assigns.current_user.id, video_id: video_id})
  {:noreply, socket}
end
```

---

## What Not to Do

- **No `Repo` calls outside context modules**
- **No cross-tenant data access** — every query must be scoped to `organization_id`
- **No multi-responsibility functions** — if in doubt, split it
- **No public function without a doctest** (exempt: DB and external service calls)
- **No untested branch** — every `case`/`cond`/`if` arm needs a test
- **No direct Mux or Stripe API calls outside their client modules**
- **No hardcoded tenant data** — slugs, domains, theme values all come from the DB
- **No `IO.inspect` left in committed code**
- **No `mix` commands in production** — use release commands only
- **No secrets in `config/config.exs` or `config/prod.exs`** — runtime only
- **No deploys that skip tests** — the `needs: test` gate is not optional
- **No business logic in TypeScript hooks** — hooks are thin DOM/JS bridges only
