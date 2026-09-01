---
name: feature_02_01_architecture_retrofit
description: Use when retrofitting existing Marquee code to follow the project’s architectural decisions, especially audit logging, service boundaries, and consistency patterns across existing features.
---

# Task: Feature 2.1 — Retrofit Architecture Patterns into Existing Codebase

Feature 02 (Super Admin Panel) has been built. This follow-up task retrofits
the architecture decisions from `.claude/architecture-decisions.md` into
everything that exists so far. Every feature built after this one will inherit
these patterns automatically.

Follow all rules in CLAUDE.md. Load `.claude/architecture-decisions.md` and
`.claude/testing.md`.

This task has 8 parts. Do them in order. Run `mix test` after each part to
confirm nothing is broken. **Existing tests must continue to pass unchanged.**
If a test fails, the new code is wrong, not the old test.

---

## Part 1: Audit Log Schema and Module

### Generate the schema and migration

```bash
mix phx.gen.schema Audit.Log audit_logs \
  organization_id:references:organizations \
  user_id:references:users \
  action:string \
  resource_type:string \
  resource_id:binary_id \
  changes:map \
  metadata:map \
  --no-scope
```

### Edit the migration

- `organization_id` nullable (some actions are platform-level, not org-scoped)
- `user_id` nullable (some actions are system-triggered, e.g. Oban workers)
- `action` not null
- `resource_type` not null
- `resource_id` nullable (some actions don't target a specific record)
- Add indexes on `[:organization_id]`, `[:user_id]`, `[:action]`,
  `[:resource_type, :resource_id]`
- Do NOT add `updated_at` — audit logs are append-only. Use
  `timestamps(updated_at: false)` in both the migration and schema.

### Edit the schema

- `belongs_to :organization` (optional)
- `belongs_to :user` (optional)
- `timestamps(type: :utc_datetime, updated_at: false)`

### Build `Marquee.Audit` module

```elixir
defmodule Marquee.Audit do
  @moduledoc "Append-only audit log for all mutating operations."

  alias Marquee.Audit.Log
  alias Marquee.Repo

  @doc """
  Logs an auditable action.

  scope can be a %Scope{} or nil (for system-level actions).
  action is a string like "video.created".
  resource is the struct that was acted on.
  changes is a map of what changed (can be empty for creates/deletes).
  """
  def log(scope, action, resource, changes \\ %{}) do
    attrs = %{
      organization_id: org_id_from_scope(scope),
      user_id: user_id_from_scope(scope),
      action: action,
      resource_type: resource_type(resource),
      resource_id: resource_id(resource),
      changes: changes,
      metadata: build_metadata(scope)
    }

    %Log{}
    |> Log.changeset(attrs)
    |> Repo.insert()
  end

  defp org_id_from_scope(nil), do: nil
  defp org_id_from_scope(%{organization: nil}), do: nil
  defp org_id_from_scope(%{organization: org}), do: org.id

  defp user_id_from_scope(nil), do: nil
  defp user_id_from_scope(%{user: nil}), do: nil
  defp user_id_from_scope(%{user: user}), do: user.id

  defp resource_type(%{__struct__: module}), do: module |> Module.split() |> List.last()
  defp resource_type(_), do: "Unknown"

  defp resource_id(%{id: id}), do: id
  defp resource_id(_), do: nil

  defp build_metadata(scope) do
    base = case Marquee.RequestContext.current() do
      nil -> %{}
      ctx -> Map.take(ctx, [:request_id, :ip, :user_agent])
    end

    # Add impersonation info if present
    case scope do
      %{impersonated_by: admin_id} when not is_nil(admin_id) ->
        Map.put(base, :impersonated_by, admin_id)
      _ ->
        base
    end
  end
end
```

### Tests

`test/marquee/audit/audit_test.exs`
- `log/4` creates an audit log with all fields populated
- `log/4` with nil scope creates a log with nil user and org
- `log/4` correctly extracts resource type and ID from structs
- Audit logs are append-only (no `updated_at` field)

---

## Part 2: Request Context Module

### Create `lib/marquee/request_context.ex`

```elixir
defmodule Marquee.RequestContext do
  @moduledoc """
  Per-process request context. Set in a plug, available everywhere
  without passing through function signatures.
  """

  @key :marquee_request_context

  def put(attrs) when is_map(attrs) do
    Process.put(@key, attrs)
  end

  def current do
    Process.get(@key)
  end

  def get(key, default \\ nil) do
    case current() do
      nil -> default
      ctx -> Map.get(ctx, key, default)
    end
  end
end
```

### Create `lib/marquee_web/plugs/set_request_context.ex`

```elixir
defmodule MarqueeWeb.Plugs.SetRequestContext do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    Marquee.RequestContext.put(%{
      request_id: Logger.metadata()[:request_id],
      ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
      user_agent: get_req_header(conn, "user-agent") |> List.first(),
      scope: conn.assigns[:current_scope]
    })
    conn
  end
end
```

### Wire into router

Add `plug MarqueeWeb.Plugs.SetRequestContext` to the `:browser` pipeline, AFTER
the auth and org resolution plugs so the scope is available.

### Tests

`test/marquee_web/plugs/set_request_context_test.exs`
- Sets request context with request_id, ip, and user_agent
- Context is accessible via `RequestContext.current/0` within the request
- Returns nil when no context has been set

---

## Part 3: Soft Deletes

### Generate migration

```bash
mix ecto.gen.migration add_soft_deletes
```

Add `deleted_at :utc_datetime` to these tables:
- `videos`
- `collections`
- `tags`
- `rows`
- `row_items`
- `watchlist_items`
- `favorites`
- `plans`
- `notifications`
- `webhook_endpoints`
- `organizations`

```elixir
def change do
  tables = [
    :videos, :collections, :tags, :rows, :row_items,
    :watchlist_items, :favorites, :plans, :notifications,
    :webhook_endpoints, :organizations
  ]

  for table <- tables do
    alter table(table) do
      add :deleted_at, :utc_datetime
    end

    create index(table, [:deleted_at])
  end
end
```

### Update every affected schema

Add to each schema listed above:

```elixir
field :deleted_at, :utc_datetime
```

Do NOT add `deleted_at` to any changeset — it's managed by the `delete_*` and
`restore_*` context functions, not by user input.

### Update every list query

Find every context function that queries these schemas and add the soft-delete
filter. The pattern:

```elixir
|> where([r], is_nil(r.deleted_at))
```

This includes functions in:
- `Content` context (videos, collections, tags)
- `Catalog` context (rows, row items)
- `Engagement` context (watchlist items, favorites)
- `Billing` context (plans)
- `Notifications` context
- `Webhooks` context (endpoints)
- `Accounts` context (organizations — only in org listing, not in resolution)
- `Admin` context (list_organizations should have an option to include deleted)

**IMPORTANT:** Do NOT add the soft-delete filter to `SetOrganization` plug
queries. A soft-deleted org should resolve for the purpose of showing a
"this site is no longer available" page, not a 404.

### Update delete functions

Convert every `Repo.delete` call to a soft delete:

```elixir
def delete_video(scope, video) do
  video
  |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
  |> Repo.update()
end
```

### Add restore functions

For each soft-deletable resource, add a restore function:

```elixir
def restore_video(scope, video) do
  video
  |> Ecto.Changeset.change(deleted_at: nil)
  |> Repo.update()
end
```

### Tests

For each affected context:
- List function excludes soft-deleted records
- Delete function sets `deleted_at` instead of removing the record
- Restore function clears `deleted_at`
- Deleted record is still retrievable via a `_including_deleted` variant
- **All existing tests must continue to pass unchanged** — the soft-delete
  filter should be transparent to tests that weren't deleting records

---

## Part 4: Pagination on List Queries

### Update every list context function

Find every function that returns a list from the database and update its
signature to accept `opts \\ []` with pagination support.

The return shape changes from a bare list to a pagination struct:

```elixir
%{
  results: [%Video{}, ...],
  page: 1,
  per_page: 25,
  total: 142,
  total_pages: 6
}
```

### Create a pagination helper

```elixir
defmodule Marquee.Pagination do
  @max_per_page 100
  @default_per_page 25

  def paginate(query, opts) do
    page = max(Keyword.get(opts, :page, 1), 1)
    per_page = opts |> Keyword.get(:per_page, @default_per_page) |> min(@max_per_page) |> max(1)

    results =
      query
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> Marquee.Repo.all()

    total = Marquee.Repo.aggregate(query, :count)

    %{
      results: results,
      page: page,
      per_page: per_page,
      total: total,
      total_pages: max(ceil(total / per_page), 1)
    }
  end
end
```

### Usage in context functions

```elixir
def list_videos(%Organization{id: org_id}, opts \\ []) do
  Video
  |> where(organization_id: ^org_id)
  |> where([v], is_nil(v.deleted_at))
  |> order_by(desc: :inserted_at)
  |> Pagination.paginate(opts)
end
```

### Update LiveViews

Every LiveView that calls a list function needs to handle the new return shape.
Update them to read `result.results` instead of the bare list. For now, none of
them need to render pagination controls — just destructure correctly.

### Update existing tests

**Do NOT change test assertions.** Instead, update the test setup to extract
results from the pagination struct:

If an existing test does:
```elixir
assert [video] = Content.list_videos(org)
```

It should now do:
```elixir
assert %{results: [video]} = Content.list_videos(org)
```

This is one of the rare cases where changing an existing test is acceptable —
the function signature changed intentionally and deliberately. The assertions
about the returned data stay the same; only the destructuring pattern changes.

### New tests

For each paginated function:
- Returns correct page of results
- Respects `per_page` option
- Clamps `per_page` to max 100
- Returns correct `total` and `total_pages`
- Page 1 is the default
- Empty result set returns `total: 0, total_pages: 1`

---

## Part 5: Event Broadcasting

### Create `lib/marquee/events.ex`

```elixir
defmodule Marquee.Events do
  @moduledoc """
  Event broadcasting for side effects. Context functions broadcast events;
  subscribers handle audit logging, webhook dispatch, analytics, and
  notifications.
  """

  def broadcast(scope, event) do
    org_id = case scope do
      %{organization: %{id: id}} -> id
      _ -> "global"
    end

    Phoenix.PubSub.broadcast(
      Marquee.PubSub,
      "events:#{org_id}",
      {:marquee_event, event, scope}
    )

    Phoenix.PubSub.broadcast(
      Marquee.PubSub,
      "events:global",
      {:marquee_event, event, scope}
    )
  end

  def subscribe(organization_id) do
    Phoenix.PubSub.subscribe(Marquee.PubSub, "events:#{organization_id}")
  end

  def subscribe_global do
    Phoenix.PubSub.subscribe(Marquee.PubSub, "events:global")
  end
end
```

### Create audit subscriber

```elixir
defmodule Marquee.Events.AuditSubscriber do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Marquee.Events.subscribe_global()
    {:ok, %{}}
  end

  def handle_info({:marquee_event, {action, resource}, scope}, state) do
    Marquee.Audit.log(scope, format_action(action), resource)
    {:noreply, state}
  end

  defp format_action(atom) when is_atom(atom) do
    atom |> Atom.to_string() |> String.replace("_", ".")
  end
end
```

Add `AuditSubscriber` to your application supervision tree in `application.ex`.

### Instrument existing context functions

Go through every context function that creates, updates, or deletes and add
an event broadcast. The pattern:

```elixir
def create_video(scope, attrs) do
  with {:ok, video} <- do_create_video(scope, attrs) do
    Events.broadcast(scope, {:video_created, video})
    {:ok, video}
  end
end
```

Do this for all mutating functions across all contexts:
- `Accounts` — org created/updated, membership created/removed
- `Content` — video created/updated/deleted, collection created/updated/deleted
- `Catalog` — row created/updated/deleted/reordered
- `Engagement` — watchlist item added/removed, favorite added/removed
- `Billing` — plan created/updated, subscription created/canceled
- `Branding` — theme updated
- `Webhooks` — endpoint created/updated/deleted
- `Admin` — org created, super admin granted/revoked

### Tests

- `Events.broadcast/2` sends to org-specific and global PubSub topics
- `AuditSubscriber` creates audit log entries when events are broadcast
- Side effects don't break the primary operation — if the subscriber
  crashes, the context function still returns `{:ok, resource}`

---

## Part 6: Consistent Error Tuples

### Audit existing context functions

Go through every context function that returns `{:error, _}` and standardize
the error shapes.

Replace:
```elixir
{:error, changeset}
```
With:
```elixir
{:error, :validation, changeset}
```

Replace:
```elixir
{:error, "not found"}
```
With:
```elixir
{:error, :not_found}
```

### Standard error atoms

Use these consistently:
- `{:error, :validation, changeset}` — Ecto validation failure
- `{:error, :not_found}` — record doesn't exist
- `{:error, :forbidden}` — user lacks permission
- `{:error, :not_authenticated}` — no user in scope
- `{:error, :plan_limit_reached, %{limit: n, current: n}}` — usage cap hit
- `{:error, :subscription_required}` — viewer needs to subscribe
- `{:error, :feature_not_enabled}` — feature flag is off for this org
- `{:error, :already_exists}` — unique constraint would be violated
- `{:error, :mux_error, details}` — Mux API failure
- `{:error, :stripe_error, details}` — Stripe API failure

### Update LiveViews to handle new error shapes

Every `case` or `with` in a LiveView that matches on `{:error, changeset}`
needs to match on `{:error, :validation, changeset}` instead.

### Update existing tests

Tests that assert on `{:error, changeset}` need to assert on
`{:error, :validation, changeset}`. This is an intentional API change — the
tests are updated to match the new contract.

---

## Part 7: Feature Flags

### Generate migration

```bash
mix ecto.gen.migration add_features_to_organizations
```

```elixir
def change do
  alter table(:organizations) do
    add :features, :map, default: %{}
  end
end
```

### Update Organization schema

```elixir
field :features, :map, default: %{}
```

### Create `lib/marquee/features.ex`

```elixir
defmodule Marquee.Features do
  alias Marquee.Accounts.Organization

  @doc """
  Checks if a feature is enabled for the given organization.

      iex> org = %Marquee.Accounts.Organization{features: %{"live_streaming" => true}}
      iex> Marquee.Features.enabled?(org, :live_streaming)
      true

      iex> org = %Marquee.Accounts.Organization{features: %{}}
      iex> Marquee.Features.enabled?(org, :live_streaming)
      false
  """
  def enabled?(%Organization{features: features}, feature) do
    Map.get(features || %{}, to_string(feature), false)
  end

  @doc """
  Returns all enabled features for an organization.
  """
  def list_enabled(%Organization{features: features}) do
    (features || %{})
    |> Enum.filter(fn {_k, v} -> v == true end)
    |> Enum.map(fn {k, _v} -> k end)
  end
end
```

### Add to super admin org edit

If the super admin OrganizationEditLive already exists, add a feature flags
section where the super admin can toggle features on/off for the org.

### Tests

- `enabled?/2` returns true when feature is set to true
- `enabled?/2` returns false when feature is missing
- `enabled?/2` returns false when features map is nil
- `list_enabled/1` returns only enabled feature names

---

## Part 8: Idempotency Key Helper and Oban Job Tagging

### Create `lib/marquee/idempotency.ex`

```elixir
defmodule Marquee.Idempotency do
  @doc """
  Generates a deterministic idempotency key for external API calls.

      iex> Marquee.Idempotency.key("create_upload", "org_123", "video_456")
      "create_upload:org_123:video_456:" <> Date.to_string(Date.utc_today())
  """
  def key(operation, org_id, resource_id) do
    "#{operation}:#{org_id}:#{resource_id}:#{Date.utc_today()}"
  end
end
```

### Verify Oban job tagging

Audit all existing Oban job insertions. Every `Oban.insert` call must include
`organization_id` in the job args. If any are missing, add them.

Search for all occurrences of `Oban.insert` and `.new(` in the codebase and
verify each one.

### Tests

- Idempotency key is deterministic for the same inputs on the same day
- Idempotency key changes on a different day
- Idempotency key changes for different operations

---

## Part 9: Update Tenant Data Export

### Create or update `Marquee.Admin.export_organization_data/1`

This function must export every tenant-scoped table. For now it returns a map:

```elixir
def export_organization_data(organization) do
  org_id = organization.id

  %{
    organization: organization,
    memberships: Repo.all(from m in Membership, where: m.organization_id == ^org_id, preload: [:user]),
    videos: Repo.all(from v in Video, where: v.organization_id == ^org_id),
    collections: Repo.all(from c in Collection, where: c.organization_id == ^org_id),
    tags: Repo.all(from t in Tag, where: t.organization_id == ^org_id),
    rows: Repo.all(from r in Row, where: r.organization_id == ^org_id),
    plans: Repo.all(from p in Plan, where: p.organization_id == ^org_id),
    subscriptions: Repo.all(from s in Subscription, where: s.organization_id == ^org_id),
    theme: Repo.get_by(Theme, organization_id: org_id),
    webhook_endpoints: Repo.all(from w in WebhookEndpoint, where: w.organization_id == ^org_id),
    notifications: Repo.all(from n in Notification, where: n.organization_id == ^org_id),
    audit_logs: Repo.all(from a in AuditLog, where: a.organization_id == ^org_id),
    watchlist_items: Repo.all(from w in WatchlistItem, where: w.organization_id == ^org_id),
    favorites: Repo.all(from f in Favorite, where: f.organization_id == ^org_id),
    watch_histories: Repo.all(from w in WatchHistory, where: w.organization_id == ^org_id),
    progresses: Repo.all(from p in Progress, where: p.organization_id == ^org_id),
    analytics_events: Repo.all(from e in AnalyticsEvent, where: e.organization_id == ^org_id),
  }
end
```

**NOTE:** This function intentionally does NOT filter soft-deleted records.
Exports include everything including deleted data, with `deleted_at` timestamps.

### Tests

- Export includes records from the target org
- Export does NOT include records from other orgs
- Export includes soft-deleted records
- Export returns empty lists (not nil) for schemas with no data

---

## Definition of Done

- [ ] Audit log schema, migration, and `Marquee.Audit` module
- [ ] `Marquee.RequestContext` module and `SetRequestContext` plug in pipeline
- [ ] `deleted_at` on all user-facing content schemas
- [ ] All list queries filter soft-deleted records
- [ ] All delete functions use soft delete
- [ ] Restore functions exist for each soft-deletable schema
- [ ] All list functions accept `opts \\ []` with pagination
- [ ] `Marquee.Pagination` helper module
- [ ] LiveViews updated to handle pagination return shape
- [ ] `Marquee.Events` module with PubSub broadcasting
- [ ] `AuditSubscriber` GenServer in supervision tree
- [ ] All mutating context functions broadcast events
- [ ] All error tuples standardized to tagged atoms
- [ ] `Marquee.Features` module with `enabled?/2`
- [ ] `features` JSONB column on organizations
- [ ] `Marquee.Idempotency` key helper
- [ ] All Oban jobs include `organization_id` in args
- [ ] `export_organization_data/1` covers all tenant-scoped tables
- [ ] All existing tests pass (updated only for intentional API changes)
- [ ] New tests cover all new modules and behaviors
- [ ] `mix format`, `mix credo --strict`, and `mix dialyzer` all pass
