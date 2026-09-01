# Task: Feature 04.1 — Viewer Accounts and User Flows

This feature builds the viewer-facing identity and access layer. Viewers are
the customers of the org — they sign up, subscribe, and watch content.

**Critical design decision: viewers are a completely separate identity from
operators.** Viewers have their own schema, their own auth tokens, their own
session, and their own email field. There is no foreign key between `Viewer`
and `User`. This is intentional — it provides hard data isolation between
orgs at the schema level, not just application-level query scoping.

Follow all rules in CLAUDE.md. Load `.claude/multi-tenancy.md`,
`.claude/architecture-decisions.md`, `.claude/scalability.md`,
`.claude/observability.md`, and `.claude/testing.md`.

This task has 8 parts. Do them in order. Run `mix test` after each part.

---

## Part 1: Data Model — Viewer (Separate from User)

### Why separate identities

The `User` schema is for **operators** — people who manage organizations via
the Marquee admin dashboard. They have `Memberships` with roles, they might
manage multiple orgs, and their identity is platform-level.

The `Viewer` schema is for **customers of an org** — people who sign up on a
tenant's site to watch content. Their identity is org-level. Key reasons for
full separation:

1. **Data breach isolation** — if an org's data is exported (breach, GDPR,
   rogue operator), it contains only that org's viewers. There's no technical
   link to viewers on other orgs. You can't accidentally leak cross-org data
   if the cross-org relationship doesn't exist.
2. **Auth isolation** — a compromised auth token on org A has zero impact on
   org B. Tokens are scoped to a single org by schema design, not by
   application logic.
3. **Operator trust boundary** — operators can see, manage, and act on their
   viewers. If viewers shared an identity across orgs, a malicious operator
   could theoretically infer information about a viewer's activity on other
   platforms.
4. **Migration simplicity** — importing viewers from Uscreen/Muvi means creating
   Viewer records per org. No cross-referencing, no deduplication, no shared
   identity concerns.
5. **User expectation** — nobody expects their Netflix login to work on Disney+.
   Viewers of org A and org B are separate customers with separate
   relationships, even if the same human is behind both.

### Schema: `Viewer`

Generate migration:

```bash
mix ecto.gen.migration create_viewers
```

```elixir
schema "viewers" do
  belongs_to :organization, Organization

  # Identity — completely separate from User
  field :email, :string
  field :display_name, :string
  field :avatar_url, :string

  # Auth
  field :hashed_password, :string
  field :confirmed_at, :utc_datetime

  # Account state
  field :status, Ecto.Enum, values: [:active, :suspended, :banned], default: :active

  # Subscription — gating infrastructure (Stripe integration in Feature 05)
  field :subscription_status, :string, default: "none"
  # Values: "none", "trial", "active", "past_due", "canceled", "expired"
  field :subscription_expires_at, :utc_datetime
  field :trial_expires_at, :utc_datetime

  # Profile
  field :onboarding_completed, :boolean, default: false
  field :marketing_opt_in, :boolean, default: false
  field :metadata, :map, default: %{}

  # Soft delete
  field :deleted_at, :utc_datetime

  timestamps(type: :utc_datetime)
end
```

Migration:
- Unique index on `[:organization_id, :email]` — one viewer per email per org
- Index on `[:organization_id]`
- Index on `[:email]`
- Index on `[:organization_id, :subscription_status]`
- `email` not null
- `status` not null, default `:active`
- `subscription_status` not null, default `"none"`

### Schema: `ViewerToken`

Viewers need their own token system for magic links and sessions, completely
separate from the operator `UserToken` table.

```elixir
schema "viewer_tokens" do
  belongs_to :viewer, Viewer
  field :token, :binary
  field :context, :string    # "session", "magic_link"
  field :sent_to, :string    # email address

  timestamps(type: :utc_datetime, updated_at: false)
end
```

Migration:
- Index on `[:token, :context]`
- Index on `[:viewer_id]`

### Update related schemas

Add `belongs_to :viewer` (NOT `belongs_to :user`) on all viewer-scoped schemas:

- `Subscription` — add `viewer_id` field (alongside existing `user_id` which
  will be deprecated for viewer subscriptions)
- `WatchHistory` — add `viewer_id`
- `Progress` — add `viewer_id`
- `WatchlistItem` — add `viewer_id`
- `Favorite` — add `viewer_id`
- `AnalyticsEvent` — add `viewer_id` (optional — some events are anonymous)

**Important:** Do NOT remove the existing `user_id` fields yet. Add `viewer_id`
as a new nullable column alongside `user_id`. The engagement features (Feature
06) will use `viewer_id`. Migration of existing `user_id` references can happen
later if needed. This lets Feature 03's existing progress tracking continue to
work during the transition.

---

## Part 2: Viewer Auth System

Build a parallel auth system for viewers. This mirrors the structure of
`phx.gen.auth` but is completely independent.

### Create `Marquee.Viewers` context

This is a new top-level context — NOT under `Accounts`. The separation is
intentional: `Accounts` manages operators, `Viewers` manages viewers.

```elixir
defmodule Marquee.Viewers do
  @moduledoc """
  Context for viewer identity and authentication. Viewers are customers of
  an organization — completely separate from the operator User/Membership
  system.
  """

  # Registration
  def register_viewer(organization, attrs)
  def change_viewer_registration(organization, attrs \\ %{})

  # Auth
  def get_viewer_by_email(organization, email)
  def get_viewer_by_session_token(token)
  def generate_viewer_session_token(viewer)
  def delete_viewer_session_token(token)

  # Magic link
  def deliver_viewer_magic_link(organization, email)
  def verify_viewer_magic_link(token)

  # CRUD
  def get_viewer(organization, id)
  def get_viewer!(organization, id)
  def update_viewer_profile(scope, viewer, attrs)
  def list_viewers(organization, opts \\ [])
  def count_viewers(organization)
  def count_viewers_by_status(organization)

  # Account actions (operator-initiated)
  def suspend_viewer(scope, viewer)
  def ban_viewer(scope, viewer)
  def reactivate_viewer(scope, viewer)
  def grant_access(scope, viewer, expires_at)
  def revoke_access(scope, viewer)

  # Deletion
  def delete_viewer(scope, viewer)  # soft delete
  def hard_delete_viewer_data(organization, viewer)  # GDPR erasure
end
```

### `register_viewer/2`

```elixir
def register_viewer(organization, attrs) do
  Telemetry.with_span "marquee.viewers.register",
    %{"marquee.org.id" => organization.id} do

    changeset = Viewer.registration_changeset(%Viewer{organization_id: organization.id}, attrs)

    case Repo.insert(changeset) do
      {:ok, viewer} ->
        Events.broadcast_org(organization, {:viewer_registered, viewer})
        Metrics.viewer_registered(organization.id)
        {:ok, viewer}

      {:error, changeset} ->
        {:error, :validation, changeset}
    end
  end
end
```

### `deliver_viewer_magic_link/2`

```elixir
def deliver_viewer_magic_link(organization, email) do
  case get_viewer_by_email(organization, email) do
    nil ->
      # Return ok to prevent email enumeration
      {:ok, :not_found}

    %Viewer{status: :banned} ->
      {:ok, :not_found}  # Don't reveal that the account exists but is banned

    %Viewer{status: :suspended} ->
      {:ok, :not_found}  # Same

    %Viewer{} = viewer ->
      {token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
      Repo.insert!(viewer_token)
      # Send email with magic link
      MarqueeWeb.ViewerNotifier.deliver_magic_link(viewer, token, organization)
      {:ok, :sent}
  end
end
```

### `verify_viewer_magic_link/1`

```elixir
def verify_viewer_magic_link(token) do
  case ViewerToken.verify_magic_link_token(token) do
    {:ok, viewer_id} ->
      viewer = Repo.get(Viewer, viewer_id)
      if viewer && is_nil(viewer.confirmed_at) do
        viewer
        |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now())
        |> Repo.update!()
      end
      {:ok, viewer}

    :error ->
      {:error, :invalid_token}
  end
end
```

### ViewerToken module

`lib/marquee/viewers/viewer_token.ex` — parallel to the existing UserToken
but for viewers. Implements:

- `build_session_token/1` — creates a session token for a viewer
- `verify_session_token/1` — validates and returns the viewer_id
- `build_magic_link_token/1` — creates a magic link token
- `verify_magic_link_token/1` — validates magic link (expires after 15 minutes)

**Token hashing and signing should use a different salt than UserToken** so
that a viewer token can never accidentally validate as an operator token,
even if the databases were somehow merged.

---

## Part 3: Viewer Session and Scope

### Viewer session — separate from operator session

Viewer sessions must be stored under different session keys than operator
sessions. This prevents any possibility of session confusion.

```elixir
# Operator session keys (existing)
:user_token

# Viewer session keys (new)
:viewer_token
```

### Create `MarqueeWeb.Hooks.AssignViewerScope`

A new on_mount hook specifically for viewer-facing routes:

```elixir
defmodule MarqueeWeb.Hooks.AssignViewerScope do
  import Phoenix.LiveView
  import Phoenix.Component

  alias Marquee.Viewers

  def on_mount(:optional_auth, _params, session, socket) do
    viewer = get_viewer_from_session(session)
    {:cont, assign(socket, current_viewer: viewer)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    case get_viewer_from_session(session) do
      nil ->
        {:halt, redirect(socket, to: "/login")}

      %{status: status} when status in [:suspended, :banned] ->
        {:halt,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> redirect(to: "/")}

      viewer ->
        {:cont, assign(socket, current_viewer: viewer)}
    end
  end

  defp get_viewer_from_session(session) do
    token = session["viewer_token"]
    token && Viewers.get_viewer_by_session_token(token)
  end
end
```

**Note:** Viewer-facing pages use `current_viewer` in assigns, NOT
`current_scope`. The scope struct is for operators. Viewers get a simpler
`current_viewer` assign that's just the `%Viewer{}` struct. This makes
the boundary crystal clear in templates:

- Admin templates check `@current_scope.membership.role`
- Viewer templates check `@current_viewer.subscription_status`

No ambiguity. No shared struct. No possibility of confusion.

### Viewer auth controller

Create `lib/marquee_web/controllers/viewer_session_controller.ex`:

Handles:
- `POST /viewer-session` — creates viewer session from magic link token
- `DELETE /viewer-session` — logs out the viewer
- `GET /viewer-session/magic-link/:token` — validates magic link, creates session

This is separate from the existing operator session controller.

---

## Part 4: Subscription Gating

### Subscription access helper

```elixir
defmodule Marquee.Viewers.SubscriptionAccess do
  alias Marquee.Viewers.Viewer

  @doc """
  Determines if a viewer has active access to gated content.

      iex> has_access?(%Viewer{subscription_status: "active"})
      true

      iex> has_access?(%Viewer{subscription_status: "none"})
      false
  """
  def has_access?(%Viewer{subscription_status: status} = viewer) do
    case status do
      "active" -> true
      "trial" -> not trial_expired?(viewer)
      "past_due" -> true  # grace period
      _ -> false
    end
  end

  def trial_expired?(%Viewer{trial_expires_at: nil}), do: true
  def trial_expired?(%Viewer{trial_expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
```

### Gating hook for LiveView

```elixir
defmodule MarqueeWeb.Hooks.RequireSubscription do
  import Phoenix.LiveView

  alias Marquee.Viewers.SubscriptionAccess

  def on_mount(:require_subscription, _params, _session, socket) do
    viewer = socket.assigns[:current_viewer]

    cond do
      is_nil(viewer) ->
        {:halt, redirect(socket, to: "/login")}

      viewer.status in [:suspended, :banned] ->
        {:halt,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> redirect(to: "/")}

      SubscriptionAccess.has_access?(viewer) ->
        {:cont, socket}

      true ->
        {:halt, redirect(socket, to: "/subscribe")}
    end
  end
end
```

### Video visibility

Add to Video schema via migration:

```elixir
alter table(:videos) do
  add :visibility, :string, default: "subscribers_only"
end
```

Values: `"public"`, `"free_with_account"`, `"subscribers_only"`

Content access check:

```elixir
defmodule Marquee.Content.AccessControl do
  alias Marquee.Viewers.SubscriptionAccess

  def can_watch?(video, viewer) do
    case video.visibility do
      "public" -> true

      "free_with_account" ->
        not is_nil(viewer)

      "subscribers_only" ->
        viewer && SubscriptionAccess.has_access?(viewer)
    end
  end
end
```

---

## Part 5: Router Structure

Restructure the router to clearly separate operator and viewer route groups
with their own session handling and hooks.

```elixir
# ──────────────────────────────────────
# Operator routes (User + Membership)
# ──────────────────────────────────────

# Operator auth
scope "/admin", MarqueeWeb.Admin do
  pipe_through [:browser, :set_organization]

  get "/login", SessionController, :new
  post "/login", SessionController, :create
  delete "/logout", SessionController, :delete
end

# Operator dashboard
live_session :admin,
  on_mount: [
    {MarqueeWeb.Hooks.AssignScope, :require_authenticated},
  ] do
  scope "/admin", MarqueeWeb.Admin do
    pipe_through [:browser, :set_organization, :require_admin]

    live "/", DashboardLive
    live "/content", ContentLive
    # ... rest of admin routes
  end
end

# Super admin (unchanged)
live_session :super_admin, ... do
  scope "/super", MarqueeWeb.Super do
    # ...
  end
end

# ──────────────────────────────────────
# Viewer routes (Viewer — separate auth)
# ──────────────────────────────────────

# Viewer auth
scope "/", MarqueeWeb.Viewer do
  pipe_through [:browser, :set_organization]

  get "/magic-link/:token", SessionController, :magic_link
  post "/viewer-session", SessionController, :create
  delete "/viewer-session", SessionController, :delete
end

# Viewer registration and login
live_session :viewer_auth,
  on_mount: [{MarqueeWeb.Hooks.AssignViewerScope, :optional_auth}] do
  scope "/", MarqueeWeb.Viewer do
    pipe_through [:browser, :set_organization]

    live "/register", RegisterLive
    live "/login", LoginLive
  end
end

# Public viewer pages (no auth required)
live_session :viewer_public,
  on_mount: [{MarqueeWeb.Hooks.AssignViewerScope, :optional_auth}] do
  scope "/", MarqueeWeb.Viewer do
    pipe_through [:browser, :set_organization]

    live "/", HomeLive
    live "/browse", BrowseLive
    live "/collections/:slug", CollectionLive
  end
end

# Authenticated viewer pages (login required, no subscription)
live_session :viewer_authenticated,
  on_mount: [{MarqueeWeb.Hooks.AssignViewerScope, :require_authenticated}] do
  scope "/", MarqueeWeb.Viewer do
    pipe_through [:browser, :set_organization]

    live "/account", AccountLive
    live "/subscribe", SubscribeLive
  end
end

# Subscribed viewer pages (login + subscription required)
live_session :viewer_subscribed,
  on_mount: [
    {MarqueeWeb.Hooks.AssignViewerScope, :require_authenticated},
    {MarqueeWeb.Hooks.RequireSubscription, :require_subscription}
  ] do
  scope "/", MarqueeWeb.Viewer do
    pipe_through [:browser, :set_organization]

    live "/watch/:id", WatchLive
    live "/watchlist", WatchlistLive
  end
end

# Webhooks (unchanged)
scope "/webhooks", MarqueeWeb do
  pipe_through :api
  post "/mux", WebhookController, :mux
  post "/stripe", WebhookController, :stripe
end
```

### Key points

- Operator auth uses `:user_token` in the session → `AssignScope` hook
- Viewer auth uses `:viewer_token` in the session → `AssignViewerScope` hook
- These are completely separate session keys, hooks, and code paths
- An operator logged into `/admin` and a viewer logged into `/watch` are
  using different session entries — they don't interfere with each other
- Admin login is at `/admin/login`, viewer login is at `/login`

---

## Part 6: Viewer-Facing LiveViews

### `RegisterLive` (`/register`)

Org-branded registration page. Uses tenant theme, shows org name.

Fields:
- Email (required)
- Display name (optional — defaults to email prefix)
- Marketing opt-in checkbox (unchecked by default)

On submit:
1. `Viewers.register_viewer(organization, attrs)`
2. `Viewers.deliver_viewer_magic_link(organization, email)`
3. Redirect to login with "Check your email" flash

**Security: no email enumeration.** If the email already exists, still show
"Check your email" and send a "you already have an account, click here to
sign in" email instead.

### `LoginLive` (`/login`)

- Email input
- "Send magic link" button

On submit — always show "Check your email for a sign-in link" regardless of
whether the email exists.

### `AccountLive` (`/account`)

- Display name editing
- Email display
- Marketing opt-in toggle
- Subscription status display
- "Cancel subscription" placeholder (Feature 05)
- "Delete my account" — soft-deletes the viewer, clears session, redirects to homepage

### `SubscribeLive` (`/subscribe`)

Plan selection placeholder for Feature 05. For now:
- Display available plans for the org
- Dev-mode button to manually set `subscription_status: "active"` for testing
- Gate the dev button behind `Mix.env() == :dev`

### `data-test` attributes

- `data-test="register-form"`
- `data-test="register-email-input"`
- `data-test="register-display-name-input"`
- `data-test="register-submit-btn"`
- `data-test="login-form"`
- `data-test="login-email-input"`
- `data-test="login-submit-btn"`
- `data-test="account-display-name"`
- `data-test="account-subscription-status"`
- `data-test="account-delete-btn"`
- `data-test="subscribe-plan-list"`
- `data-test="subscribe-dev-activate-btn"`

---

## Part 7: Viewer Management in Operator Dashboard

### Update Members page (`/admin/members`)

Split into two sections or tabs:
- **Team** — existing operator memberships
- **Viewers** — viewer accounts

### Viewer list

Table columns:
- Email
- Display name
- Subscription status (badge)
- Account status (active/suspended/banned)
- Joined date
- Last active (if tracked)

Features:
- Search by email or display name
- Filter by subscription status
- Filter by account status
- Pagination

### Viewer detail view

Click a viewer to see:
- Profile info
- Subscription status and expiry
- Watch history summary (placeholder — populated in Feature 06)
- Account status
- Actions

### Operator actions on viewers

- **Suspend** — sets status to `:suspended`. Viewer sees "account suspended"
  on next request. Reversible. Use case: payment dispute, TOS warning.
- **Ban** — sets status to `:banned`. Same UX as suspend but implies permanence.
  Reversible only by operator. Use case: TOS violation.
- **Reactivate** — restores suspended/banned to `:active`.
- **Grant access** — manually sets `subscription_status: "active"` with an
  optional `subscription_expires_at`. Use case: comp access, sponsors, reviewers.
- **Revoke access** — sets `subscription_status: "none"`.

RBAC:
- `viewer_support` role can view the list AND take actions (this is the role's
  primary purpose — supporting viewers)
- `editor` can view the list but NOT take actions
- `admin` and `owner` can do everything

### Viewer impersonation (super admin + operator)

Super admins and org operators need to see the platform exactly as a specific
viewer sees it — same subscription status, same watch history, same gating
behavior. This is essential for debugging "I can't watch this video" support
tickets.

**Two entry points:**

1. **Super admin panel** (`/super/organizations/:id`) — the org show page
   should list viewers (or link to the viewer list). Each viewer row has a
   "View as viewer" button.
2. **Operator dashboard** (`/admin/members` viewer tab) — each viewer row
   has a "View as viewer" button. Available to `viewer_support`+ roles.

**Implementation:**

When "View as viewer" is clicked:

1. Store the impersonation state in the session:
   - `impersonating_viewer_id` — the viewer being impersonated
   - `impersonating_admin_user_id` — the operator or super admin's User ID
   - `impersonating_return_path` — where to go when impersonation ends
2. Redirect to the org's viewer homepage (`/`)
3. The `AssignViewerScope` hook checks for `impersonating_viewer_id` in the
   session. If present AND the current operator session (`user_token`) belongs
   to a super admin or an org operator with `viewer_support`+ role:
   - Load the impersonated viewer
   - Set `current_viewer` to the impersonated viewer
   - Set `impersonating: true` in assigns
4. A persistent banner appears at the top of every viewer page:
   "Viewing as [viewer email]. [Stop viewing]"
5. The banner uses a visually distinct style (e.g. amber background with the
   Marquee brand accent) so it's impossible to forget you're impersonating.
6. "Stop viewing" clears the impersonation session keys and redirects to
   `impersonating_return_path`

**Security rules:**

- Only super admins can impersonate viewers on ANY org
- Org operators with `viewer_support`+ role can impersonate viewers on THEIR
  org only
- `editor` role CANNOT impersonate viewers
- Impersonation is read-only — the impersonator can navigate, watch videos,
  see the viewer's watchlist and progress, but CANNOT take actions that modify
  the viewer's data (no adding to watchlist, no changing account settings)
- All impersonation sessions are audit-logged: who impersonated whom, when,
  and for how long (log start and stop)
- Impersonation automatically expires after 1 hour (clear session keys via
  a timestamp check in the hook)

**What the impersonator sees:**

- The exact same homepage the viewer would see, including personalized rows
  (continue watching) based on the viewer's data
- The exact same gating behavior — if the viewer's subscription is expired,
  the impersonator sees the subscribe page, not the video
- The exact same content — if the viewer is banned, the impersonator sees
  the banned message
- The impersonation banner is the ONLY difference from the viewer's experience

**Implementation detail — session layering:**

The impersonation works by layering on top of the operator session, not
replacing it. The operator's `user_token` stays in the session. The
`impersonating_viewer_id` is an additional key. The `AssignViewerScope` hook
checks for impersonation first, then falls back to normal viewer auth.

This means the operator can "stop viewing" and immediately return to the
admin dashboard without re-authenticating.

```elixir
# In AssignViewerScope hook
defp get_viewer_from_session(session) do
  cond do
    # Check for impersonation first
    viewer_id = session["impersonating_viewer_id"] ->
      admin_user_id = session["impersonating_admin_user_id"]
      if authorized_to_impersonate?(admin_user_id, viewer_id) do
        viewer = Viewers.get_viewer_by_id(viewer_id)
        if viewer, do: %{viewer | __impersonating__: true}, else: nil
      else
        nil
      end

    # Normal viewer auth
    token = session["viewer_token"] ->
      Viewers.get_viewer_by_session_token(token)

    true ->
      nil
  end
end
```

Note: `__impersonating__` is a virtual field (not persisted) used by templates
to render the impersonation banner. Add it to the Viewer schema:

```elixir
field :__impersonating__, :boolean, virtual: true, default: false
```

### `data-test` attributes

- `data-test="viewer-list"`
- `data-test={"viewer-row-#{viewer.id}"}`
- `data-test="viewer-search"`
- `data-test="viewer-status-filter"`
- `data-test="viewer-subscription-filter"`
- `data-test={"suspend-viewer-#{id}"}`
- `data-test={"ban-viewer-#{id}"}`
- `data-test={"reactivate-viewer-#{id}"}`
- `data-test={"grant-access-#{id}"}`
- `data-test={"revoke-access-#{id}"}`
- `data-test={"impersonate-viewer-#{id}"}`
- `data-test="impersonation-banner"`
- `data-test="stop-impersonation-btn"`

---

## Part 8: Tests

### Schema tests

- Viewer changeset with valid attrs
- Viewer requires email and organization_id
- Email normalized to lowercase
- Unique constraint on `[organization_id, email]`
- Same email on different orgs succeeds (separate identities)
- Status enum validates allowed values
- ViewerToken build and verify for session and magic link

### Context tests

**`test/marquee/viewers/viewers_test.exs`**

Registration:
- `register_viewer/2` with valid attrs creates viewer
- `register_viewer/2` with duplicate email on same org returns error
- `register_viewer/2` with same email on different org succeeds
- `register_viewer/2` with missing email returns validation error
- `register_viewer/2` normalizes email to lowercase

Auth:
- `get_viewer_by_email/2` returns viewer for correct org
- `get_viewer_by_email/2` returns nil for wrong org (even if email exists there)
- `deliver_viewer_magic_link/2` for existing viewer succeeds
- `deliver_viewer_magic_link/2` for non-existent email returns ok (no enumeration)
- `deliver_viewer_magic_link/2` for banned viewer returns ok (no enumeration)
- `verify_viewer_magic_link/1` with valid token returns viewer
- `verify_viewer_magic_link/1` with expired token returns error
- `verify_viewer_magic_link/1` sets confirmed_at on first verification
- `generate_viewer_session_token/1` creates token
- `get_viewer_by_session_token/1` returns viewer
- `delete_viewer_session_token/1` invalidates token

CRUD:
- `get_viewer/2` scoped to org
- `get_viewer/2` returns not_found for viewer on different org
- `update_viewer_profile/3` updates display name
- `list_viewers/2` returns pagination struct
- `list_viewers/2` scoped to org (tenant isolation)
- `count_viewers/1` returns correct count
- `count_viewers_by_status/1` returns grouped counts

Actions:
- `suspend_viewer/2` sets status to suspended
- `ban_viewer/2` sets status to banned
- `reactivate_viewer/2` restores to active
- `grant_access/3` sets subscription_status to active with expiry
- `revoke_access/2` sets subscription_status to none
- `delete_viewer/2` soft-deletes
- All actions broadcast events
- All actions write audit logs

**`test/marquee/viewers/subscription_access_test.exs`**
- `has_access?/1` true for active
- `has_access?/1` true for trial within expiry
- `has_access?/1` false for expired trial
- `has_access?/1` true for past_due (grace)
- `has_access?/1` false for none
- `has_access?/1` false for canceled
- `has_access?/1` false for expired

**`test/marquee/content/access_control_test.exs`**
- `can_watch?/2` public video — accessible with nil viewer
- `can_watch?/2` free_with_account — accessible with any viewer
- `can_watch?/2` free_with_account — not accessible with nil viewer
- `can_watch?/2` subscribers_only — accessible with active subscriber
- `can_watch?/2` subscribers_only — not accessible with no subscription
- `can_watch?/2` subscribers_only — not accessible with nil viewer

### Hook and plug tests

**`test/marquee_web/hooks/assign_viewer_scope_test.exs`**
- Optional auth with valid session assigns viewer
- Optional auth without session assigns nil
- Require authenticated with valid session passes
- Require authenticated without session redirects to /login
- Suspended viewer redirected with error
- Banned viewer redirected with error

**`test/marquee_web/hooks/require_subscription_test.exs`**
- Active subscriber passes
- No viewer redirects to /login
- Suspended viewer redirected
- Banned viewer redirected
- No subscription redirects to /subscribe
- Expired trial redirects to /subscribe

### LiveView tests

**`test/marquee_web/live/viewer/register_live_test.exs`**
- Page renders with org name
- Valid registration creates viewer, shows confirmation
- Duplicate email shows same confirmation (no enumeration)
- Missing email shows validation error
- Registration on org A does not create viewer on org B

**`test/marquee_web/live/viewer/login_live_test.exs`**
- Page renders
- Submit shows "check your email" regardless of email existence
- Magic link login creates session and redirects

**`test/marquee_web/live/viewer/account_live_test.exs`**
- Shows display name and subscription status
- Display name editable
- Delete account soft-deletes and redirects

**`test/marquee_web/live/viewer/watch_live_test.exs` (update existing)**
- Public video accessible without viewer session
- Free-with-account redirects to /login when no viewer session
- Free-with-account accessible with any authenticated viewer
- Subscribers-only redirects to /subscribe when no subscription
- Subscribers-only accessible with active subscription
- Suspended viewer cannot watch gated content
- Banned viewer cannot watch gated content

**`test/marquee_web/live/admin/members_live_test.exs` (extend)**
- Viewer tab shows viewer accounts
- Search filters by email/name
- Subscription and status filters work
- Suspend/ban/reactivate actions work
- Grant/revoke access actions work
- viewer_support role can take viewer actions
- editor role can view but not act
- Viewers from other orgs not visible
- "View as viewer" button visible for viewer_support+ roles
- "View as viewer" button NOT visible for editor role

### Viewer impersonation tests

**`test/marquee_web/hooks/viewer_impersonation_test.exs`**
- Super admin can impersonate any viewer on any org
- Org operator with viewer_support+ can impersonate viewers on their org
- Org operator with editor role CANNOT impersonate viewers
- Org operator CANNOT impersonate viewers on a different org
- Impersonation sets `current_viewer` to the target viewer
- Impersonation sets `impersonating: true` in assigns
- Impersonation banner is rendered on viewer pages during impersonation
- "Stop viewing" clears impersonation and redirects to return path
- Impersonation is read-only — write actions (add to watchlist, update account) are blocked
- Impersonation auto-expires after 1 hour
- Impersonation start and stop are audit-logged
- Impersonated viewer sees the same gating as the real viewer (if subscription expired, impersonator sees /subscribe)
- Impersonated viewer sees personalized content (continue watching) from the target viewer's data

### Critical isolation tests

**`test/marquee/viewers/isolation_test.exs`**

These are the most important tests in this feature:

- Viewer registered on org A cannot be found via `get_viewer_by_email(org_b, email)`
- Viewer session token from org A does not authenticate on org B
- Viewer magic link from org A does not work on org B
- `list_viewers(org_a)` never returns org B's viewers
- Operator on org A cannot suspend a viewer on org B
- Progress/history for viewer on org A is not accessible from org B context
- `export_organization_data(org_a)` includes org A viewers only

---

## Seed data updates

Update `priv/repo/seeds.exs`:

- Create 5-10 viewers on the primary test org with varying subscription statuses
  (active, trial, none, canceled, suspended)
- Create 2-3 viewers on the secondary test org
- Ensure some viewers share the same email address across orgs (to prove isolation)

---

## Definition of Done

- [ ] `Viewer` schema — fully separate from `User`, with email and auth fields
- [ ] `ViewerToken` schema — separate token table from `UserToken`
- [ ] `Marquee.Viewers` context with registration, auth, CRUD, and operator actions
- [ ] `SubscriptionAccess` module with `has_access?/1`
- [ ] `Content.AccessControl` module with `can_watch?/2`
- [ ] Video `visibility` field (public, free_with_account, subscribers_only)
- [ ] `AssignViewerScope` hook — separate from `AssignScope`
- [ ] `RequireSubscription` hook
- [ ] Viewer session uses `:viewer_token` key (separate from `:user_token`)
- [ ] Router restructured with separate operator and viewer route groups
- [ ] `RegisterLive` with org-branded form, anti-enumeration
- [ ] `LoginLive` with magic link flow, anti-enumeration
- [ ] `AccountLive` with profile editing and delete
- [ ] `SubscribeLive` placeholder with dev-mode activation
- [ ] Viewer management in operator dashboard (list, search, filter, actions)
- [ ] RBAC: viewer_support can act, editor can view, admin can do everything
- [ ] Viewer impersonation from super admin panel (any org's viewers)
- [ ] Viewer impersonation from operator dashboard (viewer_support+ only, own org)
- [ ] Impersonation banner on all viewer pages during impersonation
- [ ] Impersonation is read-only — no write actions on viewer data
- [ ] Impersonation auto-expires after 1 hour
- [ ] Impersonation audit-logged (start and stop)
- [ ] Editor role cannot impersonate viewers
- [ ] Cross-org impersonation blocked for non-super-admins
- [ ] `viewer_id` added to engagement schemas (Progress, WatchHistory, etc.)
- [ ] `WatchLive` updated with visibility-based gating using `can_watch?/2`
- [ ] `export_organization_data/1` updated with viewers
- [ ] Seed data includes viewers with varying statuses across multiple orgs
- [ ] All mutations broadcast events and write audit logs
- [ ] All context functions wrapped in OTel spans
- [ ] Anti-enumeration on login and registration
- [ ] **Isolation tests pass** — org A viewers invisible from org B
- [ ] Session tokens scoped to org — cross-org tokens do not authenticate
- [ ] All `data-test` attributes in place
- [ ] `mix format`, `mix credo --strict`, `mix dialyzer` pass