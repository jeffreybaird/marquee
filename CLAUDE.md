# CLAUDE.md — Bobine

This file is read automatically by Claude Code on every session. Follow all rules
here without exception unless the user explicitly overrides one for a specific task.

Domain-specific rules and detailed patterns live in `.claude/`. Load the relevant
file(s) when working in a specific area:

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

---

## Project Overview

Bobine is a multi-tenant SaaS OTT video platform built with Elixir / Phoenix
1.8 / LiveView. Businesses (tenants) use an operator dashboard to manage video
content, configure their branded viewer-facing site, and monetize via
subscriptions. Video infrastructure is powered by Mux. Billing is powered by
Stripe Connect.

### Architecture Summary

- **Multi-tenant:** Shared Postgres schema with `organization_id` on every
  tenant-scoped table. Tenant resolved from subdomain or custom domain.
- **Two interfaces:**
  - Operator dashboard (`/admin/*`) — full LiveView.
  - Viewer-facing site — static HTML with LiveView islands for interactivity.
- **Super admin panel** (`/super/*`) — platform-level management above the
  tenant layer. Requires `is_super_admin` on the user.
- **Video:** Mux Elixir SDK. We never serve video bytes.
- **Billing:** Stripe Connect for viewer subscriptions. Stripe direct for
  org platform subscriptions. SaaS fee + transaction fee revenue model.
- **Background jobs:** Oban with queues separated by criticality.
- **Deployment:** Fly.io with Erlang clustering via dns_cluster.

### Context Modules

All business logic lives in context modules. LiveViews and controllers
never call `Repo` directly.

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

These principles apply to every feature, every context function, and every
schema. They are not guidelines — they are rules. Violating them creates
problems that are expensive to fix later.

For detailed patterns and code examples, see `.claude/architecture-decisions.md`,
`.claude/scalability.md`, and `.claude/observability.md`.

### 1. Protect Postgres from the Hot Path

Never write high-frequency data directly to Postgres. Playback progress,
analytics events, and any operation that fires more than once per viewer per
minute must go through a write buffer (`Bobine.Buffer` behaviour) that
batches and flushes periodically. Context function callers must never know
whether the write is buffered or direct — the interface is the same.

See `.claude/scalability.md` for the buffer pattern and which operations
require it.

### 2. Separate Read and Write Paths

Structure context functions so reads can be routed to a database replica and
writes hit the primary. Never mix reads and writes in a single function
unless transactional consistency is actually required. This enables future
read-replica routing as a configuration change, not a rewrite.

### 3. Cache Frequently-Read, Infrequently-Written Data

Organization resolution, themes, row configuration, video metadata, and
subscription status must go through `Bobine.Cache`. The cache implementation
is ETS/Cachex today, swappable to Redis later. Invalidation happens via the
event system — when an operator updates a resource, the event broadcast
triggers cache invalidation across the Fly cluster.

See `.claude/scalability.md` for what to cache and cache key conventions.

### 4. Minimize Persistent LiveView Connections

Viewer-facing pages use an islands architecture: static server-rendered HTML
with targeted LiveView components for interactive elements. Only the operator
dashboard and low-traffic viewer pages (account, watchlist management) should
be full-page LiveView. The homepage, browse pages, and video player page
should be static with LiveView islands.

Keep socket assigns lean. Load the minimum data needed for render. Never
preload entire association trees into assigns.

### 5. Broadcast Only What Multiple Processes Need

Use PubSub for content changes, subscriber events, operator actions, and
cache invalidation. Never use PubSub for per-viewer state (playback progress,
scroll position, heartbeats). All PubSub topics must be scoped to the
narrowest useful audience — `events:{org_id}`, not `events:global`.

See `.claude/scalability.md` for topic design rules.

### 6. Separate Background Jobs by Criticality

Oban queues: `critical` (payments), `default` (webhooks, notifications),
`mux`, `stripe`, `bulk` (analytics, progress flushes, exports), `imports`.
High-volume work must never share a queue with payment processing. Every
Oban job must include `organization_id` in its args.

### 7. Emit Events, Don't Inline Side Effects

Context functions broadcast events via `Bobine.Events`. Side effects (audit
logging, webhook dispatch, analytics, notifications, cache invalidation) are
handled by subscribers, not inline in the context function. Adding a new side
effect means adding a new subscriber, not modifying existing code.

See `.claude/architecture-decisions.md` for the event broadcasting pattern.

### 8. Instrument Everything

Every context mutation gets an OpenTelemetry span. Every external API call
gets a span with service-specific attributes. Every Oban worker restores
trace context from the enqueuing request. Every business-significant event
emits a metric via `Bobine.Metrics`. Every log line uses structured metadata
with `trace_id`, `span_id`, `org_id`, and `user_id`.

See `.claude/observability.md` for span naming, metric conventions, and
logging rules.

### 9. One Tenant Must Never Degrade Another

Database queries are indexed and paginated. Background jobs are queue-separated.
Cache keys are org-namespaced. Rate limiting is per-tenant. A bulk import for
one org must not starve another org's webhook processing. A misconfigured org
must not slow down other orgs' page loads.

### 10. Design Interfaces for Tomorrow, Implement for Today

Use behaviours (`Bobine.Buffer`, `Bobine.Cache`, `Bobine.Content.MuxClientBehaviour`)
so implementations can be swapped without changing callers. Use consistent
error tuples so a future API layer maps cleanly to HTTP responses. Use
pagination parameters on every list function even if the UI doesn't paginate
yet. Use feature flags to gate functionality by plan tier.

---

## Code Style Rules

## **NOTE: EVERY ADDITIONAL CODE WRITTEN THAT ADDS BEHAVIOR MUST BE ACCOMPANIED BY A TEST THAT VALIDATES SAID BEHAVIOR**

### Single Responsibility — One Function, One Job

Every function does exactly one thing. If you find yourself writing `and` in a
`@doc` description, the function needs to be split.

### Pipe-First Data Transformation

All multi-step data transformations use `|>`. The input data flows top to bottom.
Avoid intermediate variables when a pipe expresses intent more clearly.

Acceptable exceptions: when a value is used more than once, or when naming it
genuinely improves readability.

### Doctests on Every Public Function

Every public function (`def`, not `defp`) must have a `@doc` block with at least
one doctest demonstrating the happy path.

Exemptions: functions that hit the database or call external services — use
unit tests with mocks instead.

### Error Handling with Tagged Tuples

All functions that can fail return specific, serializable tagged tuples:

```elixir
{:ok, resource}
{:error, :validation, changeset}
{:error, :not_found}
{:error, :forbidden}
{:error, :plan_limit_reached, %{limit: n, current: n}}
{:error, :mux_error, details}
```

Never return bare `{:error, changeset}` — always tag the error type. Never
return string error messages from context functions.

See `.claude/architecture-decisions.md` for the full error taxonomy.

### Private Functions Are Prefixed with Intent

```elixir
defp reject_expired_subscriptions(subs)  # ✅
defp filter_subs(subs)                   # ❌

defp normalize_mux_webhook_payload(map)  # ✅
defp process_webhook(map)                # ❌
```

### Contexts Are the Public API

All database access goes through context modules. LiveViews and controllers
never call `Repo` directly. The `Admin` context is the sole exception for
cross-tenant queries, clearly documented as such.

### Soft Deletes on User-Facing Content

Never hard-delete user-facing records. Use `deleted_at` timestamps. All list
queries filter soft-deleted records by default. Provide explicit
`_including_deleted` variants for admin views.

See `.claude/architecture-decisions.md` for which schemas use soft deletes.

### Pagination on Every List Query

Every context function that returns a list accepts `opts \\ []` with `page`
and `per_page` parameters. Returns a pagination struct with `results`, `page`,
`per_page`, `total`, and `total_pages`. Max `per_page` is 100.

### Audit Every Mutation

Every create, update, and delete operation is logged via the event system
and the `AuditSubscriber`. The audit log records who did it, when, what
changed, and from which IP — including impersonation context.

---

## Tests Are a Contract, Not an Obstacle

Existing tests describe intended behavior. They are specifications, not
suggestions.

1. **Never modify an existing test to make it pass.** If a previously passing
   test fails after your changes, your changes broke intended behavior. Fix
   your code, not the test. The only exception is when we are deliberately
   and explicitly changing the behavior the test describes — and that change
   must be stated upfront.

2. **Never weaken a test assertion.** Replacing a specific assertion with a
   looser one to make a failing test pass is never acceptable.

3. **Never delete a test to resolve a failure.** A deleted test is a deleted
   specification. Flag it for discussion — do not silently remove it.

4. **Never change existing function behavior to satisfy a new test.** If
   writing a test for feature B reveals that function X needs to behave
   differently, stop and evaluate. The correct approach is to add a new
   function or parameter, not quietly change X.

5. **When a new feature causes existing tests to fail, the burden of proof
   is on the new feature.** The new code must integrate without breaking
   existing behavior.

6. **If you believe an existing test is genuinely wrong**, flag it with a
   comment and ask for confirmation before changing it.

7. **If the developer provides you with an error message or bug**,
   write a failing test that represents the expected behavior and then make it
   pass with your fix.

8. **Look for the root cause of a problem**, do not find a way to avoid an error message
   because it is the shortest route to making the desired action work. Address the underlying
   problem directly.

The test suite is a ratchet that only moves forward.

See `.claude/testing.md` for the E2E rule, Wallaby setup, factory patterns,
and the full test category requirements.

---

## Accessibility — WCAG 2.1 AA Compliance

Every UI addition or modification MUST comply with WCAG 2.1 AA. Accessibility
violations are bugs, not nice-to-haves. These rules apply to every template,
component, CSS rule, and JS hook that touches the UI.

1. **Semantic HTML over ARIA** — use `<button>`, `<a>`, `<nav>`, `<main>` etc.
   Never put `phx-click` on a `<div>` or `<span>`.
2. **Keyboard navigable** — all interactive elements reachable via Tab. Carousels
   and custom widgets support arrow keys, Escape, Enter/Space. No keyboard traps.
3. **Visible focus indicators** — never remove outlines without a replacement.
4. **ARIA labels on icon-only controls** — every button/link without visible text
   needs `aria-label`. Active nav links need `aria-current="page"`.
5. **Color contrast** — text >= 4.5:1, large text >= 3:1, UI boundaries >= 3:1.
   Never convey information by color alone.
6. **Images** — every `<img>` has `alt`. Decorative images use `alt=""`.
7. **Forms** — every input has a linked `<label>`. Errors linked via
   `aria-describedby`. Required fields marked with `required` or `aria-required`.
8. **Motion** — auto-advancing content (carousels) respects
   `prefers-reduced-motion` and has a visible pause control.
9. **Touch targets** — minimum 44x44 CSS pixels.
10. **Dynamic content** — flash messages and loading states use `aria-live` regions.

Run `/a11y-audit` (`.claude/commands/a11y-audit.md`) to audit recent UI changes
against the full checklist.

---

## What Not to Do

### Code
- **No `Repo` calls outside context modules**
- **No cross-tenant data access** — every query scoped to `organization_id`
  (except explicitly documented `Admin` context functions)
- **No multi-responsibility functions**
- **No public function without a doctest** (exempt: DB and external service calls)
- **No untested branch** — every `case`/`cond`/`if` arm needs a test
- **No `IO.inspect` left in committed code**
- **No string error messages from context functions** — use tagged atoms

### External Services
- **No direct Mux or Stripe API calls outside their client modules**
- **No external API call without an idempotency key**
- **No external API call without an OpenTelemetry span**

### Data
- **No hard deletes on user-facing content** — use soft deletes
- **No list function without pagination parameters**
- **No high-frequency writes directly to Postgres** — use a buffer
- **No unbounded preloads in socket assigns**

### Infrastructure
- **No `mix` commands in production** — use release commands only
- **No secrets in `config/config.exs` or `config/prod.exs`** — runtime only
- **No deploys that skip tests** — the `needs: test` gate is not optional
- **No PubSub for per-viewer state** — only broadcast-worthy events
- **No Oban job without `organization_id` in args**

### Frontend
- **No business logic in TypeScript hooks** — hooks are thin DOM/JS bridges
- **No CSS classes as test selectors** — use `data-test` attributes
- **No hardcoded tenant data** — slugs, domains, theme values from the DB
- **No `phx-click` on `<div>` or `<span>`** — use `<button>` or `<a>`
- **No icon-only button without `aria-label`**
- **No interactive element without a visible focus indicator**
- **No auto-advancing content without `prefers-reduced-motion` support**

### Logging
- **No string interpolation in Logger calls** — use structured metadata
- **No Logger call without `org_id` in metadata** (where org context exists)