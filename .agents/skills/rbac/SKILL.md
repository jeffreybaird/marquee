---
name: rbac
description: Use when implementing or reviewing Marquee role-based access control, membership roles, permission checks, or authorization behavior across organizations.
---

# RBAC (Role-Based Access Control)

Load this file when working on user roles, permissions, team management,
or access control enforcement.

---

## Roles

Marquee uses a flat role model per organization membership. A user's role
is stored on the `Membership` join table between `User` and `Organization`.

| Role             | Content | Team Mgmt | Analytics | Billing | Delete Org |
|------------------|---------|-----------|-----------|---------|------------|
| `owner`          | ✅      | ✅        | ✅        | ✅      | ✅         |
| `admin`          | ✅      | ✅        | ✅        | ✅      | ❌         |
| `editor`         | ✅      | ❌        | Read-only | ❌      | ❌         |
| `viewer_support` | ❌      | ❌        | ✅        | ❌      | ❌         |

### Role hierarchy

`owner` > `admin` > `editor` > `viewer_support`

Higher roles inherit all permissions of lower roles. An `owner` can do everything
an `admin` can do, and so on.

### Schema

```elixir
schema "memberships" do
  belongs_to :user, Marquee.Accounts.User
  belongs_to :organization, Marquee.Accounts.Organization
  field :role, Ecto.Enum, values: [:owner, :admin, :editor, :viewer_support]
  timestamps()
end
```

### Constraints

- Every organization must have exactly one `owner`. Ownership transfer is an
  explicit action, not a role change.
- A user can be a member of multiple organizations with different roles in each.
- Deleting a membership removes access — the user account itself persists.

---

## Enforcement

### Plug: `RequireRole`

For controller actions, use the `RequireRole` plug in the router pipeline or
directly in the controller.

```elixir
# In router — applies to all routes in this scope
scope "/admin/settings", MarqueeWeb.Admin do
  pipe_through [:browser, :require_auth, :set_organization, :require_role_admin]
  # ...
end

# The plug
defmodule MarqueeWeb.Plugs.RequireRole do
  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  def init(opts), do: opts

  def call(conn, minimum_role: role) do
    membership = conn.assigns.current_membership

    if Accounts.role_at_least?(membership, role) do
      conn
    else
      conn
      |> put_flash(:error, "You don't have permission to access this page.")
      |> redirect(to: "/admin")
      |> halt()
    end
  end
end
```

### LiveView enforcement

In LiveView `handle_event` callbacks, check roles before performing the action.
Use the `Accounts.has_role?/2` or `Accounts.role_at_least?/2` helper.

```elixir
# ✅ CORRECT — check before acting
def handle_event("delete_video", %{"id" => id}, socket) do
  if Accounts.role_at_least?(socket.assigns.current_membership, :editor) do
    {:ok, _} = Content.delete_video(socket.assigns.organization, id)
    {:noreply, assign(socket, videos: Content.list_videos(socket.assigns.organization))}
  else
    {:noreply, put_flash(socket, :error, "Insufficient permissions")}
  end
end

# ❌ WRONG — no role check
def handle_event("delete_video", %{"id" => id}, socket) do
  {:ok, _} = Content.delete_video(socket.assigns.organization, id)
  {:noreply, assign(socket, videos: Content.list_videos(socket.assigns.organization))}
end
```

### Never check roles by string comparison

Always use the `Accounts` context functions for role checks. Never compare
role strings directly.

```elixir
# ✅ CORRECT
Accounts.role_at_least?(membership, :admin)

# ❌ WRONG
membership.role == :admin || membership.role == :owner
```

---

## Role Helper Functions

These belong in the `Accounts` context:

```elixir
@role_hierarchy [:viewer_support, :editor, :admin, :owner]

@doc """
Returns true if the membership's role is at least the given minimum role.

    iex> membership = %Membership{role: :admin}
    iex> Accounts.role_at_least?(membership, :editor)
    true

    iex> membership = %Membership{role: :editor}
    iex> Accounts.role_at_least?(membership, :admin)
    false
"""
def role_at_least?(%Membership{role: role}, minimum_role) do
  role_index(role) >= role_index(minimum_role)
end

defp role_index(role) do
  Enum.find_index(@role_hierarchy, &(&1 == role)) || -1
end
```

---

## Testing RBAC

Every action that is role-restricted must have tests for:
1. A user with sufficient role — action succeeds
2. A user with insufficient role — action is denied
3. A user from a different organization — action is denied (tenant isolation)

```elixir
describe "delete_video (editor+ required)" do
  test "editor can delete a video" do
    org = insert(:organization)
    membership = insert(:membership, organization: org, role: :editor)
    video = insert(:video, organization: org)

    {:ok, view, _} = live(conn_for(membership), "/admin/content")
    view |> element("[phx-click='delete_video'][phx-value-id='#{video.id}']") |> render_click()

    assert Content.get_video(org, video.id) == nil
  end

  test "viewer_support cannot delete a video" do
    org = insert(:organization)
    membership = insert(:membership, organization: org, role: :viewer_support)
    video = insert(:video, organization: org)

    {:ok, view, _} = live(conn_for(membership), "/admin/content")
    # The delete button should not be rendered, or clicking it should flash an error
    refute has_element?(view, "[phx-click='delete_video']")
  end
end
```
