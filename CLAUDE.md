# CLAUDE.md — Bobine

Claude Code read this every session. Follow all rules no exception unless user override for specific task.

Domain rules + detail patterns live `.claude/`. Load relevant file when work in area:

- `.claude/multi-tenancy.md` — tenant scoping, query patterns, test isolation
- `.claude/mux-integration.md` — Mux client, webhooks, asset conventions
- `.claude/stripe-integration.md` — Stripe client, subscriptions, webhooks
- `.claude/deployment.md` — Fly.io, CI/CD, secrets, releases
- `.claude/rbac.md` — roles, enforcement, plugs
- `.claude/branding-and-theming.md` — CSS variables, templates, per-tenant styling
- `.claude/typescript-hooks.md` — hook conventions, file structure, events
- `.claude/testing.md` — E2E rule, Wallaby, factories, mocks, `data-test` selectors
- `.claude/architecture-decisions.md` — audit logging, soft deletes, pagination, events, error tuples, feature flags
- `.claude/observability.md` — OpenTelemetry spans, metrics, structured logging
- `.claude/scalability.md` — write buffers, caching, connection management, PubSub, rate limiting
- `.claude/brand-system.md` - Visual design and tone
- `.claude/commands/a11y-audit.md` — WCAG 2.1 AA accessibility audit slash command
- `.claude/seperation-of-concerns.md` - design guidelines for LiveView, controller, or context functions
- `.claude/frontend-map.md` — routes, LiveViews, components, JS hooks, layout hierarchy

---

## Project Overview

Bobine = multi-tenant SaaS OTT video platform. Elixir / Phoenix 1.8 / LiveView. Businesses (tenants) use operator dashboard to manage video, configure branded viewer site, monetize via subscriptions. Video = Mux. Billing = Stripe Connect.

### Architecture Summary

- **Multi-tenant:** Shared Postgres schema. `organization_id` on every tenant-scoped table. Tenant resolved from subdomain or custom domain.
- **Two interfaces:**
  - Operator dashboard (`/admin/*`) — full LiveView.
  - Viewer site — static HTML + LiveView islands for interactivity.
- **Super admin panel** (`/super/*`) — platform-level mgmt above tenant layer. Need `is_super_admin` on user.
- **Video:** Mux Elixir SDK. Never serve video bytes.
- **Billing:** Stripe Connect for viewer subs. Stripe direct for org platform subs. SaaS fee + txn fee revenue.
- **Background jobs:** Oban. Queues split by criticality.
- **Deployment:** Fly.io. Erlang cluster via dns_cluster.

### Context Modules

Business logic lives in context modules. LiveViews + controllers never call `Repo` direct.

| Context         | Responsibility                                        |
|-----------------|-------------------------------------------------------|
| `Accounts`      | Users, organizations, memberships, invitations, RBAC  |
| `Content`       | Videos, collections, tags, Mux client wrapper         |
| `Catalog`       | Homepage rows, row items, layout config               |
| `Engagement`    | Watchlists, favorites, watch history, playback progress |
| `Billing`       | Stripe subscriptions, plans, checkout                 |
| `Analytics`     | Raw events, aggregations, real-time stats             |
| `Notifications` | Push notifications, notification records, delivery    |
| `Branding`      | Per-org themes, template selection                    |
| `Webhooks`      | Outbound webhook endpoints, events, delivery          |
| `Admin`         | Super admin platform-level operations (cross-tenant)  |
| `Imports`       | Migration from other platforms                        |

---

## Architecture Principles

Apply to every feature, context function, schema. Not guidelines — rules. Violate = expensive fix later.

Detail patterns + code: `.claude/architecture-decisions.md`, `.claude/scalability.md`, `.claude/observability.md`.

### 1. Protect Postgres from the Hot Path

Never write high-frequency data direct to Postgres. Playback progress, analytics events, any op fire more than once per viewer per minute must go through write buffer (`Bobine.Buffer` behaviour) — batch + flush periodic. Caller never know buffered vs direct — same interface.

See `.claude/scalability.md` for buffer pattern + which ops need it.

### 2. Separate Read and Write Paths

Structure context functions so reads route to DB replica, writes hit primary. Never mix reads + writes in one function unless txn consistency required. Enables future read-replica routing as config change, not rewrite.

### 3. Cache Frequently-Read, Infrequently-Written Data

Org resolution, themes, row config, video metadata, subscription status go through `Bobine.Cache`. Cache impl = ETS/Cachex today, swap to Redis later. Invalidation via event system — operator updates resource → event broadcast triggers cache invalidation across Fly cluster.

See `.claude/scalability.md` for what cache + key conventions.

### 4. Minimize Persistent LiveView Connections

Viewer pages = islands architecture: static server-rendered HTML + targeted LiveView components for interactive bits. Only operator dashboard + low-traffic viewer pages (account, watchlist) full-page LiveView. Homepage, browse, video player = static + LiveView islands.

Keep socket assigns lean. Load minimum data for render. Never preload entire association trees into assigns.

### 5. Broadcast Only What Multiple Processes Need

PubSub for content changes, subscriber events, operator actions, cache invalidation. Never PubSub for per-viewer state (playback progress, scroll position, heartbeats). All PubSub topics scoped narrow — `events:{org_id}`, not `events:global`.

See `.claude/scalability.md` for topic design rules.

### 6. Separate Background Jobs by Criticality

Oban queues: `critical` (payments), `default` (webhooks, notifications), `mux`, `stripe`, `bulk` (analytics, progress flushes, exports), `imports`. High-volume work never share queue with payment. Every Oban job must include `organization_id` in args.

### 7. Emit Events, Don't Inline Side Effects

Context functions broadcast events via `Bobine.Events`. Side effects (audit log, webhook dispatch, analytics, notifications, cache invalidation) handled by subscribers, not inline. New side effect = new subscriber, not modify existing code.

See `.claude/architecture-decisions.md` for event broadcasting pattern.

### 8. Instrument Everything

Every context mutation gets OpenTelemetry span. Every external API call gets span with service attrs. Every Oban worker restores trace context from enqueuing request. Every business-significant event emits metric via `Bobine.Metrics`. Every log line use structured metadata with `trace_id`, `span_id`, `org_id`, `user_id`.

See `.claude/observability.md` for span naming, metric conventions, logging rules.

### 9. One Tenant Must Never Degrade Another

DB queries indexed + paginated. Background jobs queue-separated. Cache keys org-namespaced. Rate limiting per-tenant. Bulk import for one org must not starve another org's webhook processing. Misconfigured org must not slow other orgs' page loads.

### 10. Design Interfaces for Tomorrow, Implement for Today

Use behaviours (`Bobine.Buffer`, `Bobine.Cache`, `Bobine.Content.MuxClientBehaviour`) so impls swap without change callers. Consistent error tuples so future API layer maps clean to HTTP. Pagination params on every list function even if UI no paginate yet. Feature flags to gate by plan tier.

---

## Code Style Rules

## **NOTE: EVERY ADDITIONAL CODE WRITTEN THAT ADDS BEHAVIOR MUST BE ACCOMPANIED BY A TEST THAT VALIDATES SAID BEHAVIOR**

### Cucumber Feature Files — Required for Every User-Facing Feature

Every user-facing feature must have a Gherkin scenario in `features/`. This is not optional. A feature is not done until its user pathways are described in Gherkin and covered by step definitions.

**File placement:**
- Operator dashboard features → add scenario to the relevant `features/*.feature` file (`catalog.feature`, `content_management.feature`, etc.)
- Viewer-side features → `features/content_consumption.feature` or create a new focused file
- New domains → create `features/<domain>.feature`

**Scenario rules:**
1. One scenario per user pathway (happy path AND failure paths)
2. Scenarios written in plain English from the user's perspective
3. Every conditional UI state tested: empty state, error state, success state
4. Multi-tenant isolation tested: org A cannot see org B's data
5. RBAC tested: unauthorized role cannot perform the action

**Step definitions:**
- Shared steps (login, navigation, generic assertions) → `features/step_definitions/shared_steps.ex`
- Domain steps → `features/step_definitions/<domain>_steps.ex`
- Never duplicate step text — reuse or generalize existing steps

**Running cucumber:**
```bash
mix bobine.cucumber        # acceptance suite (context-level, no browser)
mix test --only e2e        # Wallaby suite (browser-required flows only)
```

### Single Responsibility — One Function, One Job

Every function does one thing. If write `and` in `@doc`, function needs split.

### Pipe-First Data Transformation

Multi-step transformations use `|>`. Data flows top→bottom. Avoid intermediate vars when pipe expresses intent clearer.

Exception: value used more than once, or naming improves readability.

### Doctests on Every Public Function

Every public function (`def`, not `defp`) must have `@doc` block with at least one doctest for happy path.

Exempt: functions hit DB or call external services — use unit tests with mocks.

### Error Handling with Tagged Tuples

All fallible functions return specific, serializable tagged tuples:

```elixir
{:ok, resource}
{:error, :validation, changeset}
{:error, :not_found}
{:error, :forbidden}
{:error, :plan_limit_reached, %{limit: n, current: n}}
{:error, :mux_error, details}
```

Never return bare `{:error, changeset}` — always tag error type. Never return string error messages from context functions.

See `.claude/architecture-decisions.md` for full error taxonomy.

### Private Functions Are Prefixed with Intent

```elixir
defp reject_expired_subscriptions(subs)  # ✅
defp filter_subs(subs)                   # ❌

defp normalize_mux_webhook_payload(map)  # ✅
defp process_webhook(map)                # ❌
```

### Contexts Are the Public API

All DB access through context modules. LiveViews + controllers never call `Repo` direct. `Admin` context = sole exception for cross-tenant queries, clearly documented.

### Soft Deletes on User-Facing Content

Never hard-delete user-facing records. Use `deleted_at` timestamps. All list queries filter soft-deleted by default. Provide explicit `_including_deleted` variants for admin views.

See `.claude/architecture-decisions.md` for which schemas use soft deletes.

### Pagination on Every List Query

Every context function returning list accepts `opts \\ []` with `page` + `per_page`. Returns pagination struct with `results`, `page`, `per_page`, `total`, `total_pages`. Max `per_page` = 100.

### Audit Every Mutation

Every create, update, delete logged via event system + `AuditSubscriber`. Audit log records who, when, what changed, from which IP — including impersonation context.

## Git process: Trunk-Based Development & Atomic Commits

### Core rules

- Work off `main`.
- Keep branches short-lived.
- Rebase frequent onto latest `main`.
- Never create merge commits.
- Maintain clean, linear history.
- Ship in small, safe increments.

### Workflow

- Pull latest `main`
- Make small, focused change
- Commit immediately (atomic)
- Repeat
- Rebase often to stay current

Before **every commit**:

- Run `mix bobine.verify`
- Run `mix test`

No commit if checks fail.

### Atomic commits

Each commit must:

- Do one thing
- Contain only related changes
- Leave codebase in valid, working state
- Be independently understandable + reviewable

Avoid:

- Mix refactors + behavior changes
- Large, multi-purpose commits
- "WIP", "misc", "fix stuff" commits
- Broken intermediate states (unless safely gated)

### Commit structure (build in layers)

Commit in this order when possible:

1. **Scaffold** (types, files, interfaces)
2. **Logic** (core behavior)
3. **Integration** (wiring)
4. **Validation** (tests, checks)
5. **Cleanup** (refactors, naming)

### Commit messages

Format:

- `feat: add search query parser`
- `fix: prevent empty submission`
- `refactor: extract enrollment mapper`
- `test: cover edge cases`

Be specific. Describe what changed.

### History hygiene

Before open or land PR:

- Rebase onto latest `main`
- Clean commit history (squash/reorder as needed)
- Remove WIP/debug commits
- History reads clear, top → bottom

### Non-atomic work

If change can't be atomic:

- Use feature flags or guards
- Break into safe intermediate steps
- Land in multiple commits, each valid alone

### Goal

- `main` always releasable
- History linear + readable
- Every commit intentional + reversible

---

## Tests Are a Contract, Not an Obstacle

Existing tests describe intended behavior. Specifications, not suggestions.

1. **Never modify existing test to make it pass.** Previously-passing test fails after your changes = your changes broke intended behavior. Fix code, not test. Only exception: deliberately + explicitly changing the behavior the test describes — change stated upfront.

2. **Never weaken a test assertion.** Replacing specific assertion with looser one to pass failing test = never acceptable.

3. **Never delete a test to resolve a failure.** Deleted test = deleted spec. Flag for discussion — no silent remove.

4. **Never change existing function behavior to satisfy a new test.** Test for feature B reveals function X needs different behavior → stop + evaluate. Correct: add new function or param, not quietly change X.

5. **New feature causes existing tests to fail → burden of proof on new feature.** New code must integrate without breaking existing behavior.

6. **If you believe existing test genuinely wrong**, flag with comment + ask for confirmation before change.

7. **If developer gives error message or bug**, write failing test for expected behavior then make pass with your fix.

8. **Look for root cause**, don't find way to avoid error message as shortest route. Address underlying problem direct.

Test suite = ratchet, only moves forward.

See `.claude/testing.md` for E2E rule, Wallaby setup, factory patterns, full test category requirements.

---

## Accessibility — WCAG 2.1 AA Compliance

Every UI add or mod MUST comply with WCAG 2.1 AA. A11y violations = bugs, not nice-to-haves. Rules apply to every template, component, CSS rule, JS hook touching UI.

1. **Semantic HTML over ARIA** — use `<button>`, `<a>`, `<nav>`, `<main>` etc. Never `phx-click` on `<div>` or `<span>`.
2. **Keyboard navigable** — all interactive elements reach via Tab. Carousels + custom widgets support arrow keys, Escape, Enter/Space. No keyboard traps.
3. **Visible focus indicators** — never remove outlines without replacement.
4. **ARIA labels on icon-only controls** — every button/link without visible text needs `aria-label`. Active nav links need `aria-current="page"`.
5. **Color contrast** — text >= 4.5:1, large text >= 3:1, UI boundaries >= 3:1. Never convey info by color alone.
6. **Images** — every `<img>` has `alt`. Decorative images use `alt=""`.
7. **Forms** — every input has linked `<label>`. Errors linked via `aria-describedby`. Required fields marked with `required` or `aria-required`.
8. **Motion** — auto-advancing content (carousels) respects `prefers-reduced-motion` + has visible pause control.
9. **Touch targets** — min 44x44 CSS pixels.
10. **Dynamic content** — flash messages + loading states use `aria-live` regions.

Run `/a11y-audit` (`.claude/commands/a11y-audit.md`) to audit recent UI against full checklist.

---

## What Not to Do

### Code
- **No `Repo` calls outside context modules**
- **No cross-tenant data access** — every query scoped to `organization_id` (except documented `Admin` context functions)
- **No multi-responsibility functions**
- **No public function without doctest** (exempt: DB + external service calls)
- **No untested branch** — every `case`/`cond`/`if` arm needs test
- **No `IO.inspect` left in committed code**
- **No string error messages from context functions** — use tagged atoms

### External Services
- **No direct Mux or Stripe API calls outside their client modules**
- **No external API call without idempotency key**
- **No external API call without OpenTelemetry span**

### Data
- **No hard deletes on user-facing content** — use soft deletes
- **No list function without pagination params**
- **No high-frequency writes direct to Postgres** — use buffer
- **No unbounded preloads in socket assigns**

### Infrastructure
- **No `mix` commands in production** — release commands only
- **No secrets in `config/config.exs` or `config/prod.exs`** — runtime only
- **No deploys that skip tests** — `needs: test` gate not optional
- **No PubSub for per-viewer state** — only broadcast-worthy events
- **No Oban job without `organization_id` in args**

### Frontend
- **No business logic in TypeScript hooks** — hooks = thin DOM/JS bridges
- **No CSS classes as test selectors** — use `data-test` attributes
- **No hardcoded tenant data** — slugs, domains, theme values from DB
- **No `phx-click` on `<div>` or `<span>`** — use `<button>` or `<a>`
- **No icon-only button without `aria-label`**
- **No interactive element without visible focus indicator**
- **No auto-advancing content without `prefers-reduced-motion` support**

### Logging
- **No string interpolation in Logger calls** — use structured metadata
- **No Logger call without `org_id` in metadata** (where org context exists)