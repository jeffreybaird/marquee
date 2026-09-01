---
name: architecture
description: Use when creating or changing Marquee schemas, context functions, background jobs, or cross-cutting infrastructure patterns such as audit logging, outbox flows, and architectural conventions.
---

# Architecture Decisions

Load this file when creating new schemas, context functions, or system
infrastructure. These patterns are decisions made early to avoid costly
retrofits later. Follow them in all new code.

---

## Audit Logging

Every context function that creates, updates, or deletes a record must write
an audit log entry. No exceptions.

### Schema

```elixir
schema "audit_logs" do
  belongs_to :organization, Organization
  belongs_to :user, User
  field :action, :string         # "video.created", "member.invited", "plan.updated"
  field :resource_type, :string  # "Video", "Membership", "Plan"
  field :resource_id, :binary_id
  field :changes, :map           # %{"title" => %{"from" => "old", "to" => "new"}}
  field :metadata, :map          # IP, user agent, impersonation flag
  timestamps(updated_at: false)
end
```

### Usage

Call `Marquee.Audit.log/4` at the end of every mutating context function:

```elixir
def update_video(scope, video, attrs) do
  with {:ok, updated} <- do_update_video(video, attrs) do
    Audit.log(scope, "video.updated", updated, changeset_changes(video, updated))
    {:ok, updated}
  end
end
```

### Action naming convention

Use `resource.verb` format: `video.created`, `video.updated`, `video.deleted`,
`member.invited`, `member.removed`, `subscription.canceled`, `theme.updated`,
`organization.settings_updated`.

### What to log in metadata

- `request_id` — the Phoenix request ID for correlation
- `ip` — remote IP from the request
- `impersonated_by` — super admin user ID if impersonating (critical for audit trail)

---

## Request Context

A `Marquee.RequestContext` module stores per-process context that is available
everywhere without passing it through function signatures.

### Set in a plug

```elixir
defmodule MarqueeWeb.Plugs.SetRequestContext do
  def call(conn, _opts) do
    Marquee.RequestContext.put(%{
      request_id: Logger.metadata()[:request_id],
      ip: to_string(:inet_parse.ntoa(conn.remote_ip)),
      user_agent: Plug.Conn.get_req_header(conn, "user-agent") |> List.first(),
      scope: conn.assigns[:current_scope]
    })
    conn
  end
end
```

### Access anywhere

```elixir
ctx = Marquee.RequestContext.current()
ctx.request_id  # for structured logs
ctx.ip          # for audit logs
ctx.scope       # for the current user/org
```

### Rules

- Set the request context early in the plug pipeline, after auth and org resolution
- The audit logger reads from request context automatically — individual context
  functions do not need to pass request metadata explicitly
- Oban workers should set their own context at the start of `perform/1` with
  the job's metadata (org ID, triggering user, etc.)

---

## Soft Deletes

Never hard-delete user-facing records. Add a `deleted_at` timestamp to every
content-related schema and filter it out by default.

### Which schemas get soft deletes

- Video
- Collection
- Tag
- Row
- RowItem
- WatchlistItem
- Favorite
- Plan
- Notification
- Webhook Endpoint
- Organization (deactivated, not destroyed)

### Which schemas use hard deletes

- WatchHistory (append-only log, deleted via GDPR data erasure only)
- Progress (overwritten, not deleted)
- Analytics Event (append-only log)
- Audit Log (never deleted, retention policy handled separately)
- Membership (removing a member is immediate and permanent)
- Webhook Delivery (pruned by age via Oban-style cleanup)

### Implementation

Add to every soft-deletable schema:

```elixir
field :deleted_at, :utc_datetime
```

Add a migration for each:

```elixir
alter table(:videos) do
  add :deleted_at, :utc_datetime
end
```

### Query pattern

Every list/get function must exclude soft-deleted records by default:

```elixir
# ✅ CORRECT — filters out deleted records
def list_videos(%Organization{id: org_id}) do
  Video
  |> where(organization_id: ^org_id)
  |> where([v], is_nil(v.deleted_at))
  |> order_by(desc: :inserted_at)
  |> Repo.all()
end

# For admin/super admin "show deleted" views
def list_videos_including_deleted(%Organization{id: org_id}) do
  Video
  |> where(organization_id: ^org_id)
  |> order_by(desc: :inserted_at)
  |> Repo.all()
end
```

### Deletion function pattern

```elixir
def delete_video(scope, video) do
  video
  |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
  |> Repo.update()
  |> tap(fn {:ok, deleted} ->
    Audit.log(scope, "video.deleted", deleted, %{})
    Events.broadcast(scope, {:video_deleted, deleted})
  end)
end
```

### Restoration

Provide `restore_video/2` that sets `deleted_at` back to nil. Log it as
`video.restored`.

---

## Pagination on Every List Query

Every context function that returns a list must accept pagination options,
even if the UI doesn't paginate yet.

### Interface

```elixir
def list_videos(%Organization{id: org_id}, opts \\ []) do
  page = Keyword.get(opts, :page, 1)
  per_page = Keyword.get(opts, :per_page, 25)
  order_by = Keyword.get(opts, :order_by, [desc: :inserted_at])

  query =
    Video
    |> where(organization_id: ^org_id)
    |> where([v], is_nil(v.deleted_at))
    |> order_by(^order_by)

  results = query
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()

  total = Repo.aggregate(query, :count)

  %{
    results: results,
    page: page,
    per_page: per_page,
    total: total,
    total_pages: ceil(total / per_page)
  }
end
```

### Rules

- Default `per_page` is 25. Max is 100. Enforce the max in the function.
- Always return the pagination metadata alongside results — the UI will
  need it eventually even if it ignores it now.
- For functions where you're certain the result set is always small (e.g.
  `list_memberships` for an org which will have <20 members), pagination is
  optional but the `opts \\ []` parameter should still be present.

---

## Event-Driven Side Effects

Mutating context functions broadcast events. Side effects (audit logging,
webhook dispatch, analytics, notifications) are handled by subscribers,
not inline in the context function.

### Broadcasting

```elixir
def create_video(scope, attrs) do
  with {:ok, video} <- do_create_video(scope, attrs) do
    Marquee.Events.broadcast(scope, {:video_created, video})
    {:ok, video}
  end
end
```

### Subscribing

```elixir
defmodule Marquee.Events.AuditSubscriber do
  @events [:video_created, :video_updated, :video_deleted,
           :member_invited, :member_removed, :subscription_canceled]

  def handle_event(scope, {event, resource}) when event in @events do
    Audit.log(scope, format_action(event), resource, %{})
  end
end

defmodule Marquee.Events.WebhookSubscriber do
  def handle_event(scope, {event, resource}) do
    Webhooks.dispatch(scope.organization, event, resource)
  end
end
```

### Implementation

Use Phoenix PubSub for in-process event distribution. The `Marquee.Events`
module is a thin wrapper:

```elixir
defmodule Marquee.Events do
  def broadcast(scope, event) do
    Phoenix.PubSub.broadcast(
      Marquee.PubSub,
      "events:#{scope.organization.id}",
      {event, scope}
    )
    # Also broadcast to global topic for platform-wide listeners
    Phoenix.PubSub.broadcast(Marquee.PubSub, "events:global", {event, scope})
  end
end
```

### Rules

- Context functions only broadcast events — they do not call audit, webhook,
  or notification modules directly.
- Adding a new side effect means adding a new subscriber, not modifying an
  existing context function. This preserves the "tests are a contract" rule.
- Events are fire-and-forget from the context function's perspective. If a
  subscriber fails, it must not break the primary operation.
- For side effects that must be reliable (webhook delivery), the subscriber
  enqueues an Oban job rather than doing the work inline.

---

## Idempotency Keys on External API Calls

Every call to Mux or Stripe must include an idempotency key.

### Pattern

```elixir
defmodule Marquee.Content.MuxClient do
  @impl true
  def create_upload_url(params) do
    key = idempotency_key("create_upload", params.organization_id, params.title)
    # Pass key in Mux API request headers
  end

  defp idempotency_key(operation, org_id, resource_identifier) do
    "#{operation}:#{org_id}:#{resource_identifier}:#{Date.utc_today()}"
  end
end
```

### Rules

- Generate deterministic keys from operation + org + resource identifier +
  date bucket. This ensures retries within the same day use the same key.
- Never generate random idempotency keys — that defeats the purpose.
- Log the idempotency key at `debug` level for troubleshooting.

---

## Feature Flags Per Organization

Organizations have a `features` JSONB column for feature gating.

### Schema

```elixir
# On Organization
field :features, :map, default: %{}
```

### Helper

```elixir
defmodule Marquee.Features do
  @doc """
  Checks if a feature is enabled for the given organization.

      iex> org = %Organization{features: %{"live_streaming" => true}}
      iex> Marquee.Features.enabled?(org, :live_streaming)
      true

      iex> org = %Organization{features: %{}}
      iex> Marquee.Features.enabled?(org, :live_streaming)
      false
  """
  def enabled?(%Organization{features: features}, feature) do
    Map.get(features || %{}, to_string(feature), false)
  end
end
```

### Usage in LiveViews

```elixir
<div :if={Features.enabled?(@organization, :catalog_rows)}>
  <.link navigate={~p"/admin/catalog"}>Catalog</.link>
</div>
```

### Rules

- Default is always `false` — features are opt-in.
- Feature flags gate UI rendering AND context function access. Check both:
  the LiveView should not render the feature, AND the context function should
  return `{:error, :feature_not_enabled}` if called directly.
- Use feature flags for plan-tier differentiation. Starter orgs get base
  features. Growth orgs get advanced features. Scale orgs get everything.
- Super admins can toggle feature flags per org from the super admin panel.

---

## Consistent Error Tuples

All context functions return tagged tuples with specific, serializable error
atoms. This prepares for a future public API without rewriting the context layer.

### Error shapes

```elixir
# Success
{:ok, resource}
{:ok, resource, metadata}

# Validation error (changeset)
{:error, :validation, changeset}

# Not found
{:error, :not_found}

# Authorization
{:error, :forbidden}
{:error, :not_authenticated}

# Business logic
{:error, :plan_limit_reached, %{limit: 100, current: 100}}
{:error, :subscription_required}
{:error, :feature_not_enabled}
{:error, :already_exists}

# External service failure
{:error, :mux_error, details}
{:error, :stripe_error, details}
```

### Rules

- Never return bare `{:error, changeset}` — always tag it as
  `{:error, :validation, changeset}` so the caller knows the error type
  without inspecting the value.
- Never return string error messages from context functions. Strings are for
  the UI layer (LiveView flash messages), not the context layer.
- Error atoms must be meaningful enough to map to HTTP status codes:
  `:not_found` → 404, `:forbidden` → 403, `:validation` → 422,
  `:plan_limit_reached` → 402 or 403.

---

## Tenant Data Export

Maintain a `Marquee.Admin.export_organization_data/1` function that exports
all data for an organization. Keep it updated as new schemas are added.

### What to export

Every tenant-scoped table: videos (including soft-deleted), collections, tags,
rows, subscribers, memberships, themes, plans, subscriptions, webhook endpoints,
audit logs, analytics events, watch history, watchlist items, favorites, progress.

### Format

Return a map of lists, serializable to JSON:

```elixir
%{
  organization: org_data,
  videos: [...],
  collections: [...],
  subscribers: [...],
  audit_logs: [...],
  # etc.
}
```

### Rules

- Update this function every time a new tenant-scoped schema is added. If you
  add a table and forget to add it here, data portability is broken.
- This function intentionally crosses the soft-delete boundary — it exports
  deleted records too, marked with their `deleted_at` timestamp.
- This is also the foundation for the GDPR data export feature.

---

## Oban Job Tagging

Every Oban job must include the `organization_id` in its args for monitoring
and fair scheduling.

### Pattern

```elixir
%{organization_id: org.id, video_id: video.id, payload: payload}
|> Marquee.Workers.MuxWebhookProcessor.new()
|> Oban.insert()
```

### Rules

- Never enqueue an Oban job without `organization_id` in the args (unless
  it is genuinely a platform-level job like cleanup or aggregation).
- Use Oban's unique constraints scoped to `organization_id` + resource ID
  where appropriate to prevent duplicate processing.
- Log `organization_id` at the start of every worker's `perform/1` for
  per-tenant debugging.

---

## Summary Checklist for New Features

When adding a new feature, verify:

- [ ] New schema has `deleted_at` if it's user-facing content
- [ ] New schema has `organization_id` if it's tenant-scoped
- [ ] Context list functions accept `opts \\ []` with pagination
- [ ] Context list functions filter out soft-deleted records by default
- [ ] Context mutation functions broadcast events via `Marquee.Events`
- [ ] Context mutation functions return specific error atoms, not strings
- [ ] External API calls include idempotency keys
- [ ] Oban jobs include `organization_id` in args
- [ ] `export_organization_data/1` is updated to include the new data
- [ ] Feature is gated behind a feature flag if it's plan-tier dependent
- [ ] All `data-test` attributes are in place
- [ ] All user pathways have LiveView tests
