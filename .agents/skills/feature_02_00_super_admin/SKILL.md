---
name: feature_02_00_super_admin
description: Use when implementing or reviewing Bobine’s platform-level super admin panel, super admin user capabilities, tenant onboarding, or platform management workflows.
---

# Task: Implement Super Admin Panel for Platform Management

This feature adds a Bobine platform-level admin interface that sits above the
tenant layer. Super admins manage organizations, onboard new tenants, and monitor
platform health. This is completely separate from the per-org operator dashboard.

Follow all rules in CLAUDE.md. Load `.claude/multi-tenancy.md`, `.claude/rbac.md`,
and `.claude/testing.md` for conventions.

This task has 6 parts. Do them in order. Run `mix test` after each part.

---

## Part 1: Add Super Admin Flag to User Schema

### Generate migration

```bash
mix ecto.gen.migration add_super_admin_to_users
```

The migration should add:
- `is_super_admin` boolean, default `false`, null `false`

```elixir
def change do
  alter table(:users) do
    add :is_super_admin, :boolean, default: false, null: false
  end
end
```

### Update User schema

Add the field to `lib/bobine/accounts/user.ex`:

```elixir
field :is_super_admin, :boolean, default: false
```

Do NOT include `is_super_admin` in any public changeset. This field is only set
via seeds, `iex`, or a super admin action — never through a user-facing form.
Create a separate `admin_changeset/2` that allows setting this field, and
restrict its usage to the super admin context.

### Why a boolean on User, not a role on Membership

Super admins are not members of any specific organization. They operate above
the tenant layer. Putting super admin status on Membership would require creating
a fake "platform" organization, which pollutes the multi-tenant model. A simple
boolean on User is clean and unambiguous.

---

## Part 2: Build the RequireSuperAdmin Plug

Create `lib/bobine_web/plugs/require_super_admin.ex`.

This plug checks `current_scope.user.is_super_admin`. It does NOT check
organization or membership — super admin routes are org-independent.

```elixir
defmodule BobineWeb.Plugs.RequireSuperAdmin do
  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    scope = conn.assigns[:current_scope]

    cond do
      is_nil(scope) or is_nil(scope.user) ->
        conn
        |> put_flash(:error, "You must be logged in.")
        |> redirect(to: "/")
        |> halt()

      scope.user.is_super_admin ->
        conn

      true ->
        conn
        |> put_flash(:error, "Access denied.")
        |> redirect(to: "/")
        |> halt()
    end
  end
end
```

### LiveView on_mount hook

Create `lib/bobine_web/hooks/require_super_admin.ex` for LiveView routes:

```elixir
defmodule BobineWeb.Hooks.RequireSuperAdmin do
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:require_super_admin, _params, _session, socket) do
    scope = socket.assigns[:current_scope]

    if scope && scope.user && scope.user.is_super_admin do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, "Access denied.")
       |> redirect(to: "/")}
    end
  end
end
```

---

## Part 3: Super Admin Context

Create a new context module: `lib/bobine/admin.ex`

This context provides platform-level queries that intentionally cross tenant
boundaries. Every function in this module should have a comment acknowledging
that it is a cross-tenant query — this is the one place where unscoped queries
are acceptable.

### Functions to implement

```elixir
defmodule Bobine.Admin do
  @moduledoc """
  Platform-level admin context. Functions in this module intentionally
  query across all tenants. They are only callable from super admin
  interfaces.
  """

  @doc "Lists all organizations with summary stats."
  def list_organizations(opts \\ []) do
    # Returns all orgs, optionally with:
    # - member_count (preloaded or subquery)
    # - video_count (preloaded or subquery)
    # - subscriber_count (preloaded or subquery)
    # - platform_subscription status
    # Supports opts: :order_by, :search (filter by name/slug)
  end

  @doc "Gets a single organization with full details."
  def get_organization!(id) do
    # Preload theme, platform_subscription, platform_plan
  end

  @doc "Creates a new organization."
  def create_organization(attrs) do
    # Creates the org
    # Creates a default theme
    # Returns {:ok, organization} or {:error, changeset}
  end

  @doc "Updates an organization."
  def update_organization(organization, attrs) do
    # Standard update
  end

  @doc "Deletes an organization and all its data."
  def delete_organization(organization) do
    # Cascading delete (FK on_delete: :delete_all handles most of this)
    # Log this action — it's destructive
  end

  @doc "Creates an owner membership for a user in an organization."
  def create_owner_membership(organization, user) do
    # Creates a membership with role: :owner
    # Validates that the org doesn't already have an owner
  end

  @doc "Lists all users with super admin status."
  def list_super_admins do
    User |> where(is_super_admin: true) |> Repo.all()
  end

  @doc "Grants super admin status to a user."
  def grant_super_admin(user) do
    user |> User.admin_changeset(%{is_super_admin: true}) |> Repo.update()
  end

  @doc "Revokes super admin status from a user."
  def revoke_super_admin(user) do
    user |> User.admin_changeset(%{is_super_admin: false}) |> Repo.update()
  end

  @doc """
  Returns platform-wide summary stats.
  Used for the super admin dashboard.
  """
  def platform_stats do
    %{
      total_organizations: Repo.aggregate(Organization, :count),
      total_users: Repo.aggregate(User, :count),
      total_videos: Repo.aggregate(Video, :count),
      total_subscribers: Repo.aggregate(Subscription, :count),
      # Add more as needed
    }
  end
end
```

---

## Part 4: Wire Up Super Admin Routes

Update `lib/bobine_web/router.ex`.

Super admin routes live at `/super` and do NOT go through the `set_organization`
pipeline. They are org-independent.

```elixir
# Super admin routes — no org resolution, requires super admin
live_session :super_admin,
  on_mount: [
    {BobineWeb.Hooks.AssignScope, :require_authenticated},
    {BobineWeb.Hooks.RequireSuperAdmin, :require_super_admin}
  ] do
  scope "/super", BobineWeb.Super do
    pipe_through [:browser, :require_authenticated_user]

    live "/", DashboardLive
    live "/organizations", OrganizationsLive
    live "/organizations/new", OrganizationNewLive
    live "/organizations/:id", OrganizationShowLive
    live "/organizations/:id/edit", OrganizationEditLive
    live "/users", UsersLive
  end
end
```

### Important: no SetOrganization in the pipeline

The super admin routes must NOT include the `set_organization` plug. These routes
operate above the tenant layer. The `current_scope` will have a `user` but no
`organization` or `membership`.

---

## Part 5: Build the Super Admin LiveViews

### Super admin layout component

Create `lib/bobine_web/components/super_layout.ex` — similar to the admin layout
but with its own sidebar navigation. Visually distinguish it from the org admin
dashboard so there's no confusion about which context you're in. Use a different
accent color or a "Bobine Platform" header.

Sidebar links:
- Dashboard (`/super`)
- Organizations (`/super/organizations`)
- Users (`/super/users`)

Display the current user's email and a "Super Admin" badge.

### `DashboardLive` (`/super`)

Shows platform-wide stats from `Admin.platform_stats/0`:
- Total organizations
- Total users across all orgs
- Total videos across all orgs
- Total active subscribers across all orgs

Use `data-test` attributes: `data-test="stat-total-orgs"`, etc.

### `OrganizationsLive` (`/super/organizations`)

A table listing all organizations with:
- Name
- Slug
- Custom domain (if set)
- Member count
- Video count
- Created date
- Link to "View" (show page)

Include a search input that filters by name or slug (use `phx-change` for
live filtering). Include a "New Organization" button linking to the new form.

Add `data-test` attributes:
- `data-test="org-table"`
- `data-test={"org-row-#{org.id}"}`
- `data-test="org-search"`
- `data-test="new-org-btn"`

### `OrganizationNewLive` (`/super/organizations/new`)

A form to create a new organization with fields:
- Name (required)
- Slug (required, auto-generated from name with a "customize" option)
- Custom domain (optional)
- Owner email (required — the email of the user who will be the owner)

On submit:
1. Create the organization
2. Create a default theme for the org
3. Look up or create the user by email
4. Create an owner membership
5. Redirect to the org show page with a success flash

If the owner email doesn't match an existing user, create a new user account
and trigger the magic link welcome email so they can set up their account.

### `OrganizationShowLive` (`/super/organizations/:id`)

Shows full details for a single organization:
- Name, slug, custom domain
- Theme preview (show the brand colors as swatches)
- Members list with roles
- Video count
- Subscriber count
- Platform subscription status (when billing is implemented)

Action buttons:
- Edit organization
- "Open as Admin" — navigates to `/admin` with a mechanism to view the org's
  operator dashboard as if you were their admin. Implementation: set the org
  in the session temporarily. This is the impersonation feature.

Add `data-test="impersonate-btn"`.

### `OrganizationEditLive` (`/super/organizations/:id/edit`)

Edit form for org name, slug, custom domain. Same validation as the new form.
On success, redirect back to the show page.

### `UsersLive` (`/super/users`)

A table of all users across the platform:
- Email
- Super admin status (badge)
- Number of org memberships
- Created date

Actions:
- Grant/revoke super admin status (with confirmation)
- Link to view their memberships

### Impersonation

The "Open as Admin" feature on the org show page allows a super admin to view
any org's operator dashboard. Implementation approach:

1. When the super admin clicks "Open as Admin", store the target
   `organization_id` in the session under a key like `impersonated_org_id`
2. Also store the super admin's user ID under `impersonating_user_id` so you
   can display a banner and provide a "Stop impersonating" action
3. Update the `SetOrganization` plug to check for `impersonated_org_id` first
   — if present and the current user is a super admin, use that org instead
   of resolving from the host
4. Display a persistent banner at the top of the admin dashboard:
   "You are viewing [Org Name] as a super admin. [Stop impersonating]"

This is essential for support and debugging. Without it, you'd need test accounts
in every org to troubleshoot customer issues.

---

## Part 6: Tests

### Context tests (`test/bobine/admin/admin_test.exs`)

- `list_organizations/0` returns all orgs
- `list_organizations/1` with search filters by name
- `get_organization!/1` returns org with preloads
- `get_organization!/1` raises for nonexistent ID
- `create_organization/1` with valid attrs creates org + default theme
- `create_organization/1` with missing name returns error
- `create_organization/1` with duplicate slug returns error
- `create_owner_membership/2` creates owner membership
- `create_owner_membership/2` fails if org already has an owner
- `platform_stats/0` returns correct counts
- `grant_super_admin/1` sets the flag
- `revoke_super_admin/1` clears the flag

### Plug tests (`test/bobine_web/plugs/require_super_admin_test.exs`)

- Super admin user can access protected route
- Regular user is redirected
- Unauthenticated request is redirected

### LiveView tests

`test/bobine_web/live/super/dashboard_live_test.exs`
- Super admin can access dashboard
- Non-super-admin user is redirected
- Unauthenticated user is redirected
- Dashboard displays platform stats with correct counts

`test/bobine_web/live/super/organizations_live_test.exs`
- Lists all organizations
- Search filters results
- "New Organization" button is visible
- Non-super-admin cannot access

`test/bobine_web/live/super/organization_new_live_test.exs`
- Creates org with valid data → redirects to show page
- Creates default theme for the new org
- Creates owner membership for the specified email
- Creates a new user if email doesn't exist
- Shows validation errors for missing required fields
- Shows error for duplicate slug

`test/bobine_web/live/super/organization_show_live_test.exs`
- Displays org details
- Shows member list
- Impersonate button is present
- Non-super-admin cannot access

`test/bobine_web/live/super/users_live_test.exs`
- Lists all users
- Shows super admin badge for super admins
- Grant super admin action works
- Revoke super admin action works (with confirmation)
- Cannot revoke your own super admin status

### Impersonation tests

- Super admin can impersonate an org and see their admin dashboard
- Impersonation banner is visible during impersonation
- "Stop impersonating" clears the session and returns to super admin panel
- Non-super-admin cannot trigger impersonation
- Impersonating super admin sees the org's data, not their own

### Update seed script

Update `priv/repo/seeds.exs` to also create:
- A super admin user (email: `super@bobine.dev`, `is_super_admin: true`)
- A second organization (name: "Test Channel", slug: "test-channel") with its
  own owner, theme, and a couple of members — so the super admin dashboard
  has meaningful data to display

---

## Definition of Done

- [ ] `is_super_admin` boolean on User schema, with migration
- [ ] `admin_changeset/2` on User for setting super admin flag (not in public changeset)
- [ ] `RequireSuperAdmin` plug and LiveView on_mount hook
- [ ] `Bobine.Admin` context with all listed functions
- [ ] Super admin routes at `/super` — no org resolution in pipeline
- [ ] Super admin layout component with distinct visual identity
- [ ] DashboardLive showing platform stats
- [ ] OrganizationsLive with search and list
- [ ] OrganizationNewLive — creates org + theme + owner membership
- [ ] OrganizationShowLive with details and impersonate button
- [ ] OrganizationEditLive
- [ ] UsersLive with grant/revoke super admin
- [ ] Impersonation flow — session-based, banner, stop action
- [ ] Seed script creates super admin user and multiple orgs
- [ ] All tests pass including access control and impersonation
- [ ] `mix format`, `mix credo --strict`, and `mix dialyzer` all pass
- [ ] Every public function has a doctest
- [ ] Every interactive element has a `data-test` attribute
