# Multi-Tenancy Rules

Load this file when working on any feature that touches tenant-scoped data.

---

## Core Principle

Bobine is a shared-schema multi-tenant application. Every tenant (organization)
shares the same Postgres database and the same tables. Isolation is enforced at the
application layer, not the database layer.

---

## Schema Rules

### Every tenant-scoped table has `organization_id`

No exceptions. If data belongs to a tenant, it has an `organization_id` foreign key
with an index. The only tables without it are `organizations` itself and
system-level tables (e.g. Oban jobs, global feature flags).

```elixir
# ✅ CORRECT — every tenant table
schema "videos" do
  belongs_to :organization, Bobine.Accounts.Organization
  field :title, :string
  # ...
  timestamps()
end

def changeset(video, attrs) do
  video
  |> cast(attrs, [:title, :organization_id, ...])
  |> validate_required([:title, :organization_id])
  |> foreign_key_constraint(:organization_id)
end
```

### Composite unique constraints include `organization_id`

Any uniqueness constraint (e.g. video slug, plan name) must be scoped to the
organization. A slug that's unique globally is wrong — it should be unique per-org.

```elixir
# ✅ CORRECT
|> unique_constraint([:slug, :organization_id])

# ❌ WRONG — globally unique slug prevents two orgs from using the same slug
|> unique_constraint([:slug])
```

### Migration pattern

```elixir
def change do
  create table(:videos) do
    add :organization_id, references(:organizations, on_delete: :delete_all), null: false
    add :title, :string, null: false
    # ...
    timestamps()
  end

  create index(:videos, [:organization_id])
  create unique_index(:videos, [:slug, :organization_id])
end
```

Always use `on_delete: :delete_all` on the organization FK so that deleting an
organization cascades cleanly. Never use `:nothing` or `:nilify_all` — orphaned
tenant data is a data integrity bug.

---

## Query Rules

### All context functions scope to organization

Context functions that return tenant data must accept an `%Organization{}` or
`organization_id` as the first argument.

```elixir
# ✅ CORRECT — organization scopes the query
def list_videos(%Organization{id: org_id}) do
  Video
  |> where(organization_id: ^org_id)
  |> order_by(desc: :inserted_at)
  |> Repo.all()
end

def get_video(%Organization{id: org_id}, video_id) do
  Video
  |> where(organization_id: ^org_id, id: ^video_id)
  |> Repo.one()
end

# ❌ WRONG — returns data across all tenants
def list_videos do
  Repo.all(Video)
end

# ❌ WRONG — fetches by ID without org scoping (data leak risk)
def get_video(video_id) do
  Repo.get(Video, video_id)
end
```

### Never expose unscoped queries

The only functions that may query across tenants are explicit system/admin
functions, clearly namespaced and documented:

```elixir
# Acceptable — clearly marked as system-level
defmodule Bobine.Admin do
  @doc "System-level: returns all organizations. Not for tenant use."
  def list_all_organizations do
    Repo.all(Organization)
  end
end
```

---

## Tenant Resolution

### Plug: `SetOrganization`

Tenant is resolved from the request in this order:

1. **Custom domain** — look up `organizations` by `custom_domain` field
2. **Subdomain** — extract subdomain from host, look up by `slug`
3. **Fallback** — 404 if no tenant is resolved

The resolved `%Organization{}` is placed in:
- `conn.assigns.organization` (for controller actions)
- Propagated to `socket.assigns.organization` in LiveView `on_mount`

### LiveView mount

Every LiveView that renders tenant-scoped content must read `organization` from
socket assigns. The `on_mount` hook handles this — individual LiveViews do not
resolve the tenant themselves.

```elixir
# In the router
live_session :viewer, on_mount: [{BobineWeb.Hooks.AssignOrganization, :assign}] do
  live "/", HomeLive
  live "/watch/:id", WatchLive
end
```

---

## Test Isolation

### Every test creates its own organization

Never rely on a shared/global organization across tests. Each test case inserts
its own org via the factory.

```elixir
test "lists only videos for the given organization" do
  org_a = insert(:organization)
  org_b = insert(:organization)
  video_a = insert(:video, organization: org_a)
  _video_b = insert(:video, organization: org_b)

  result = Content.list_videos(org_a)
  assert length(result) == 1
  assert hd(result).id == video_a.id
end
```

### Always test cross-tenant isolation

For every context function that reads data, include a test that verifies org A
cannot see org B's data. This is not optional — it is the most important category
of test in a multi-tenant system.
