---
name: feature_01_multi_tenant_resolution
description: Use when implementing or reviewing the foundational multi-tenant scope resolution flow, organization-aware auth scope wiring, and the initial admin dashboard shell for Marquee.
---

# Task: Implement Multi-Tenant Resolution and Admin Dashboard Shell

This is the foundational feature that every subsequent feature depends on. Follow
all rules in CLAUDE.md. Load `.claude/multi-tenancy.md`, `.claude/rbac.md`, and
`.claude/testing.md` for domain-specific conventions.

This task has 6 parts. Do them in order. Run `mix test` after each part to confirm
nothing is broken before proceeding.

---

## Part 1: Extend the Phoenix 1.8 Scope to Include Organization

Phoenix 1.8's `phx.gen.auth` generated a `Scope` struct at
`lib/marquee/accounts/scope.ex` that holds the current user. Extend it to also
carry the current organization and membership.

### Modify `lib/marquee/accounts/scope.ex`

The scope struct should contain:
- `user` — the authenticated `%User{}` (already exists from gen.auth)
- `organization` — the resolved `%Organization{}` for the current tenant
- `membership` — the `%Membership{}` joining the user to the org (contains role)

Add constructor functions:
```elixir
def for_user(%User{} = user), do: %__MODULE__{user: user}
def for_user(nil), do: nil

def with_organization(%__MODULE__{} = scope, %Organization{} = org, %Membership{} = membership) do
  %{scope | organization: org, membership: membership}
end
```

### Why

Every LiveView and controller action needs access to the current user, their
organization, and their role within that organization. The scope is the single
container that carries all of this through the request lifecycle. Context
functions receive the scope and use it for query scoping and authorization.

---

## Part 2: Build the SetOrganization Plug

Create `lib/marquee_web/plugs/set_organization.ex`.

This plug resolves the current tenant from the request and adds the organization
and membership to the scope.

### Resolution order

1. **Custom domain** — check if the request host matches any `organizations.custom_domain`
2. **Subdomain** — extract the first subdomain segment from the host, look up `organizations.slug`
3. **No match** — return 404

### For local development

In dev, the host will be `localhost` with no subdomain. Support a fallback
mechanism for development: check for an `x-marquee-org` header, or a `?org=slug`
query parameter, or default to the first organization in the database. Gate this
behind `Mix.env() == :dev` — it must never be available in production.

### Implementation

```elixir
defmodule MarqueeWeb.Plugs.SetOrganization do
  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3]
  alias Marquee.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case resolve_organization(conn) do
      {:ok, organization} ->
        # Update the scope with the organization and membership
        scope = conn.assigns[:current_scope]

        if scope && scope.user do
          case Accounts.get_membership(organization, scope.user) do
            %Membership{} = membership ->
              updated_scope = Scope.with_organization(scope, organization, membership)
              assign(conn, :current_scope, updated_scope)

            nil ->
              # User is authenticated but not a member of this org
              # This is fine for viewer routes — they may be a subscriber, not an operator
              assign(conn, :organization, organization)
          end
        else
          # No authenticated user — just set the org for public/viewer pages
          assign(conn, :organization, organization)
        end

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(404, "Not found")
        |> halt()
    end
  end

  defp resolve_organization(conn) do
    # Try custom domain first, then subdomain, then dev fallback
    with {:error, _} <- resolve_by_custom_domain(conn.host),
         {:error, _} <- resolve_by_subdomain(conn.host) do
      resolve_dev_fallback(conn)
    end
  end

  # Implement resolve_by_custom_domain/1, resolve_by_subdomain/1,
  # and resolve_dev_fallback/1 as private functions.
  # resolve_dev_fallback/1 must only work when Mix.env() == :dev
end
```

### Add context functions to `Accounts`

The plug needs these functions in the `Accounts` context:

- `get_organization_by_custom_domain(domain)` — returns `{:ok, org}` or `{:error, :not_found}`
- `get_organization_by_slug(slug)` — returns `{:ok, org}` or `{:error, :not_found}`
- `get_membership(organization, user)` — returns `%Membership{}` or `nil`

All of these are straightforward Repo queries. Write them with doctests where
possible and full unit tests including the "not found" cases.

---

## Part 3: Build the RequireRole Plug

Create `lib/marquee_web/plugs/require_role.ex`.

This plug checks whether the current user's membership has a sufficient role
to access the route. It reads the minimum required role from the plug options.

### Implementation

```elixir
defmodule MarqueeWeb.Plugs.RequireRole do
  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]
  alias Marquee.Accounts

  def init(opts), do: opts

  def call(conn, minimum_role: role) do
    scope = conn.assigns[:current_scope]

    cond do
      is_nil(scope) or is_nil(scope.membership) ->
        conn
        |> put_flash(:error, "You must be logged in to access this page.")
        |> redirect(to: "/")
        |> halt()

      Accounts.role_at_least?(scope.membership, role) ->
        conn

      true ->
        conn
        |> put_flash(:error, "You don't have permission to access this page.")
        |> redirect(to: "/admin")
        |> halt()
    end
  end
end
```

### Add role helper functions to `Accounts`

```elixir
@role_hierarchy [:viewer_support, :editor, :admin, :owner]

def role_at_least?(%Membership{role: role}, minimum_role) do
  role_index(role) >= role_index(minimum_role)
end

defp role_index(role) do
  Enum.find_index(@role_hierarchy, &(&1 == role)) || -1
end
```

Write doctests for `role_at_least?/2` covering every role combination.

---

## Part 4: Wire Up the Router

Update `lib/marquee_web/router.ex` to create the admin pipeline and route structure.

### Pipelines

Add these pipeline definitions:

```elixir
pipeline :set_organization do
  plug MarqueeWeb.Plugs.SetOrganization
end

pipeline :require_admin do
  plug MarqueeWeb.Plugs.RequireRole, minimum_role: :viewer_support
end
```

### Route structure

```elixir
# Public viewer routes (org resolved, no auth required)
scope "/", MarqueeWeb.Viewer do
  pipe_through [:browser, :set_organization]

  live "/", HomeLive
end

# Authenticated viewer routes (org resolved, auth required, subscription checked)
scope "/", MarqueeWeb.Viewer do
  pipe_through [:browser, :set_organization, :require_authenticated_user]

  live "/watch/:id", WatchLive
  live "/watchlist", WatchlistLive
  live "/account", AccountLive
end

# Admin routes (org resolved, auth required, role checked)
scope "/admin", MarqueeWeb.Admin do
  pipe_through [:browser, :set_organization, :require_authenticated_user, :require_admin]

  live "/", DashboardLive
  live "/content", ContentLive
  live "/catalog", CatalogLive
  live "/analytics", AnalyticsLive
  live "/branding", BrandingLive
  live "/members", MembersLive
  live "/webhooks", WebhooksLive
  live "/settings", SettingsLive
end

# Webhook receiver routes (no auth, no session, raw body)
scope "/webhooks", MarqueeWeb do
  pipe_through :api

  post "/mux", WebhookController, :mux
  post "/stripe", WebhookController, :stripe
end
```

### LiveView on_mount

Create a `MarqueeWeb.Hooks.AssignScope` module that reads the scope from the
session and assigns it to the socket on mount. Wire it into the live_session
blocks in the router:

```elixir
live_session :admin,
  on_mount: [{MarqueeWeb.Hooks.AssignScope, :require_authenticated}] do
  # admin routes here
end
```

The `on_mount` hook should:
1. Load the user from the session token
2. Resolve the organization (from the socket's host or URI)
3. Load the membership
4. Build the full scope and assign it to the socket
5. Assign convenience keys: `socket.assigns.current_user`,
   `socket.assigns.organization`, `socket.assigns.current_membership`

---

## Part 5: Build the Admin Dashboard Shell

Create placeholder LiveViews for the admin dashboard. Each one only needs to
render its page title and the shared admin layout. The point is to have the
skeleton in place.

### Admin layout component

Create `lib/marquee_web/components/admin_layout.ex` — a function component that
renders the admin sidebar navigation and a content area.

The sidebar should include links to:
- Dashboard (`/admin`)
- Content (`/admin/content`)
- Catalog (`/admin/catalog`)
- Analytics (`/admin/analytics`)
- Branding (`/admin/branding`)
- Members (`/admin/members`)
- Webhooks (`/admin/webhooks`)
- Settings (`/admin/settings`)

Highlight the current page in the sidebar based on the current route.

Display the organization name and the current user's email somewhere in the
layout (header or sidebar top).

### Placeholder LiveViews

Create these files, each rendering a minimal page with the admin layout:

```
lib/marquee_web/live/admin/dashboard_live.ex
lib/marquee_web/live/admin/content_live.ex
lib/marquee_web/live/admin/catalog_live.ex
lib/marquee_web/live/admin/analytics_live.ex
lib/marquee_web/live/admin/branding_live.ex
lib/marquee_web/live/admin/members_live.ex
lib/marquee_web/live/admin/webhooks_live.ex
lib/marquee_web/live/admin/settings_live.ex
```

Each should follow this pattern:

```elixir
defmodule MarqueeWeb.Admin.ContentLive do
  use MarqueeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Content")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
    >
      <.header>Content</.header>
      <p>Content management coming soon.</p>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end
end
```

### Viewer placeholder LiveViews

Also create minimal placeholders for:

```
lib/marquee_web/live/viewer/home_live.ex
lib/marquee_web/live/viewer/watch_live.ex
lib/marquee_web/live/viewer/watchlist_live.ex
lib/marquee_web/live/viewer/account_live.ex
```

These just need to render the page title with the org's name. They'll be built
out in later features.

---

## Part 6: Seed Script and Tests

### Seed script

Update `priv/repo/seeds.exs` to create:

1. A test organization (name: "Demo Studio", slug: "demo")
2. A default theme for that organization
3. An admin user with an owner membership in the org
4. An editor user with an editor membership
5. A viewer user with a viewer_support membership

This lets any developer run `mix ecto.reset` and immediately have a working
local environment with an org, users, and roles.

### Tests

Write the following tests:

**Plug tests:**

`test/marquee_web/plugs/set_organization_test.exs`
- Resolves org by custom domain
- Resolves org by subdomain
- Returns 404 when no org matches
- Sets organization in conn assigns
- Updates scope with membership when user is a member
- Handles authenticated user who is not a member of the org

`test/marquee_web/plugs/require_role_test.exs`
- Allows access when role meets minimum
- Denies access when role is below minimum
- Redirects unauthenticated users
- Owner can access editor-minimum routes
- viewer_support cannot access admin-minimum routes

**Context tests:**

`test/marquee/accounts/accounts_test.exs` (extend existing)
- `get_organization_by_slug/1` — found and not found
- `get_organization_by_custom_domain/1` — found, not found, nil domain
- `get_membership/2` — found, not found, wrong org
- `role_at_least?/2` — every role combination

**LiveView tests:**

`test/marquee_web/live/admin/dashboard_live_test.exs`
- Admin can access dashboard
- Editor can access dashboard
- viewer_support can access dashboard
- Unauthenticated user is redirected
- User from different org cannot access this org's dashboard
- Dashboard displays organization name

Write similar basic access tests for each admin placeholder LiveView. They'll
be expanded when the actual features are built, but the access control tests
should exist now.

**Add `data-test` attributes** to the admin layout sidebar links and the org
name display so tests can target them reliably:
- `data-test="admin-nav-content"`
- `data-test="admin-nav-catalog"`
- `data-test="admin-nav-analytics"`
- `data-test="org-name"`
- etc.

---

## Definition of Done

- [ ] Scope struct carries user, organization, and membership
- [ ] SetOrganization plug resolves tenant from subdomain and custom domain
- [ ] Dev fallback allows local development without subdomains
- [ ] RequireRole plug enforces role hierarchy
- [ ] Router has admin, viewer, and webhook route scopes
- [ ] LiveView on_mount hook builds the full scope and assigns it to socket
- [ ] Admin sidebar layout component renders with navigation
- [ ] All 8 admin placeholder LiveViews mount and render behind auth + role check
- [ ] All 4 viewer placeholder LiveViews mount and render
- [ ] Seed script creates a usable local development environment
- [ ] All tests pass including multi-tenant isolation and RBAC coverage
- [ ] `mix format`, `mix credo --strict`, and `mix dialyzer` all pass
- [ ] Every public function has a doctest
- [ ] Every `data-test` attribute is in place for test selectors
