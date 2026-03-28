# Testing

Load this file when writing tests, setting up test infrastructure, or reviewing
test coverage.

---

## Test Structure

```
test/
├── bobine/                           # Unit & context tests
│   ├── accounts/
│   ├── content/
│   ├── billing/
│   ├── engagement/
│   ├── catalog/
│   ├── analytics/
│   ├── branding/
│   ├── webhooks/
│   └── workers/                      # Oban worker tests
├── bobine_web/
│   ├── live/                         # LiveViewTest integration tests
│   │   ├── admin/
│   │   └── viewer/
│   ├── controllers/
│   └── e2e/                          # Wallaby browser tests (tagged :e2e)
│       ├── viewer_watch_video_test.exs
│       ├── admin_row_builder_test.exs
│       └── stripe_checkout_test.exs
├── support/
│   ├── conn_case.ex
│   ├── data_case.ex
│   ├── wallaby_case.ex               # Wallaby test case template
│   ├── factory.ex                    # ExMachina factory
│   └── mocks.ex                      # Mox mock definitions
└── fixtures/
    └── mux_webhooks/
        ├── asset_ready.json
        └── upload_asset_ready.json
```

---

## The E2E Rule

**Every user-facing feature must have end-to-end test coverage of every
possible user pathway.** This is not optional. A feature is not done until its
pathways are tested.

### What "every possible user pathway" means

For a given feature, enumerate every way a user can interact with it and every
outcome that can result. Each pathway gets a test. Examples:

**Feature: "Add to Watchlist" button on a video page**
- Authenticated subscriber clicks button → video appears in watchlist
- Authenticated subscriber clicks button on already-watchlisted video → video removed
- Unauthenticated viewer clicks button → redirected to login
- Authenticated user without subscription clicks button → redirected to subscribe
- Button renders in "added" state when video is already in watchlist on page load

**Feature: Admin video upload**
- Admin uploads valid video → video created, Mux upload triggered, success flash
- Admin uploads with missing title → validation error displayed
- Editor role uploads → succeeds (editor has content permissions)
- Viewer_support role attempts upload → denied
- Upload from a different organization's admin → cannot access

### Prefer LiveViewTest over Wallaby

LiveViewTest is the default tool for E2E pathway coverage. It is fast, async,
runs without a browser, and covers the vast majority of user interactions.

**Use LiveViewTest for:**
- Page rendering and conditional content
- Form submission (valid and invalid)
- `phx-click`, `phx-submit`, `phx-change` events
- Navigation between pages
- Flash messages
- Multi-tenant isolation
- RBAC enforcement
- Subscription gating
- Real-time updates via PubSub

**Use Wallaby ONLY for things LiveViewTest cannot cover:**
- TypeScript hooks actually executing (Mux Player mounts and plays)
- JavaScript-driven interactions (drag-and-drop, sortable lists)
- Real Stripe Checkout redirect → return flow
- CSS/visual rendering verification
- Flows that depend on client-side JS state

### Wallaby tests are tagged and excluded by default

All Wallaby test modules must have `@moduletag :e2e`. They are excluded from
`mix test` by default and only run in CI or when explicitly included:

```bash
# Normal development
mix test                    # Runs everything EXCEPT :e2e

# Run only E2E
mix test --only e2e         # Requires Chrome + ChromeDriver

# CI runs both as separate jobs
```

---

## Test Selector Convention: `data-test` Attributes

All interactive and conditionally rendered elements in LiveView templates must
have `data-test` attributes. Tests target these attributes, never CSS classes
or DOM structure.

```heex
<%!-- ✅ CORRECT — test-stable selector --%>
<button phx-click="delete_video" data-test={"delete-video-#{@video.id}"}>
  Delete
</button>

<div :if={@videos == []} data-test="empty-state">
  No videos yet.
</div>

<%!-- ❌ WRONG — fragile, breaks when you change styling --%>
<button phx-click="delete_video" class="btn btn-danger text-sm">
  Delete
</button>
```

Naming convention for `data-test` values:
- Actions: `delete-video-{id}`, `subscribe-btn`, `add-to-watchlist-{id}`
- Containers: `video-list`, `row-list`, `watchlist`
- Items: `video-{id}`, `row-{id}`, `subscriber-{id}`
- States: `empty-state`, `loading-state`, `error-state`
- Navigation: `nav-admin`, `nav-content`, `nav-analytics`

---

## Test Foundations

### DataCase

All context/unit tests use `Bobine.DataCase` which sets up the Ecto sandbox.

```elixir
defmodule Bobine.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Bobine.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Bobine.DataCase
      import Bobine.Factory
    end
  end

  setup tags do
    Bobine.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Bobine.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
```

### ConnCase

Integration and LiveView tests use `BobineWeb.ConnCase`.

```elixir
defmodule BobineWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint BobineWeb.Endpoint
      use BobineWeb, :verified_routes
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Bobine.Factory
      import BobineWeb.ConnCase
    end
  end

  setup tags do
    Bobine.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "Authenticates the connection as the given user with the given membership."
  def authenticate(conn, user, membership) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> put_session(:user_id, user.id)
    |> put_session(:membership_id, membership.id)
    |> assign(:current_user, user)
    |> assign(:current_membership, membership)
    |> assign(:organization, membership.organization)
  end

  @doc "Builds an authenticated conn for a membership."
  def conn_for(membership) do
    user = membership.user
    build_conn() |> authenticate(user, membership)
  end
end
```

### WallabyCase

Browser-based E2E tests use `BobineWeb.WallabyCase`.

```elixir
defmodule BobineWeb.WallabyCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.DSL
      import Wallaby.Query
      import Bobine.Factory

      @endpoint BobineWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Bobine.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Bobine.Repo, {:shared, self()})
    end

    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Bobine.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)
    {:ok, session: session}
  end
end
```

---

## Factories (ExMachina)

Use `ExMachina` for test data. Every tenant-scoped factory must include an
`organization` association.

```elixir
defmodule Bobine.Factory do
  use ExMachina.Ecto, repo: Bobine.Repo

  def organization_factory do
    %Bobine.Accounts.Organization{
      name: sequence(:name, &"Test Org #{&1}"),
      slug: sequence(:slug, &"test-org-#{&1}"),
    }
  end

  def user_factory do
    %Bobine.Accounts.User{
      email: sequence(:email, &"user-#{&1}@example.com"),
    }
  end

  def membership_factory do
    %Bobine.Accounts.Membership{
      user: build(:user),
      organization: build(:organization),
      role: :editor,
    }
  end

  def video_factory do
    %Bobine.Content.Video{
      organization: build(:organization),
      title: sequence(:title, &"Video #{&1}"),
      mux_asset_id: sequence(:mux_asset_id, &"asset_#{&1}"),
      mux_playback_id: sequence(:mux_playback_id, &"playback_#{&1}"),
      mux_status: "ready",
    }
  end

  def plan_factory do
    %Bobine.Billing.Plan{
      organization: build(:organization),
      name: "Monthly",
      stripe_price_id: sequence(:stripe_price_id, &"price_#{&1}"),
      amount: 999,
      interval: :monthly,
    }
  end

  def subscription_factory do
    %Bobine.Billing.Subscription{
      organization: build(:organization),
      user: build(:user),
      plan: build(:plan),
      stripe_subscription_id: sequence(:stripe_sub_id, &"sub_#{&1}"),
      status: :active,
    }
  end

  def theme_factory do
    %Bobine.Branding.Theme{
      organization: build(:organization),
      brand_primary: "#1a73e8",
      brand_secondary: "#174ea6",
      background: "#0f0f0f",
      font_heading: "Inter",
      font_body: "Inter",
    }
  end

  def row_factory do
    %Bobine.Catalog.Row{
      organization: build(:organization),
      title: sequence(:title, &"Row #{&1}"),
      source_type: :curated,
      position: sequence(:position, & &1),
      visible: true,
    }
  end

  def watchlist_item_factory do
    %Bobine.Engagement.WatchlistItem{
      organization: build(:organization),
      user: build(:user),
      video: build(:video),
      position: sequence(:position, & &1),
      auto_remove_on_watch: false,
    }
  end
end
```

---

## Mocks (Mox)

### Setup

```elixir
# test/support/mocks.ex
Mox.defmock(Bobine.Content.MockMuxClient,
  for: Bobine.Content.MuxClientBehaviour)

Mox.defmock(Bobine.Billing.MockStripeClient,
  for: Bobine.Billing.StripeClientBehaviour)
```

```elixir
# config/test.exs
config :bobine, :mux_client, Bobine.Content.MockMuxClient
config :bobine, :stripe_client, Bobine.Billing.MockStripeClient
```

### Usage pattern

```elixir
import Mox

setup :verify_on_exit!

test "handles Mux asset ready webhook" do
  org = insert(:organization)
  video = insert(:video, organization: org, mux_status: "preparing")

  expect(MockMuxClient, :get_asset, fn asset_id ->
    assert asset_id == video.mux_asset_id
    {:ok, %{duration: 120.5, max_stored_resolution: "1080p"}}
  end)

  payload = %{
    "type" => "video.asset.ready",
    "data" => %{"id" => video.mux_asset_id}
  }

  assert :ok = perform_job(MuxWebhookProcessor, %{payload: payload})

  updated = Content.get_video!(org, video.id)
  assert updated.mux_status == "ready"
  assert updated.duration == 120.5
end
```

---

## Oban Testing

Use `Oban.Testing` to assert jobs are enqueued and to execute them in tests.

```elixir
use Oban.Testing, repo: Bobine.Repo

test "webhook controller enqueues processing job" do
  conn = build_conn()
  |> put_req_header("content-type", "application/json")
  |> post("/webhooks/mux", Jason.encode!(%{type: "video.asset.ready", ...}))

  assert response(conn, 200)
  assert_enqueued(worker: Bobine.Workers.MuxWebhookProcessor)
end
```

---

## Required Test Categories

For every new feature, ALL of the following test types are required before the
feature is considered complete:

### 1. Schema/changeset tests
- Valid attrs → valid changeset
- Missing required fields → errors
- Invalid values → errors
- Unique constraint violations → errors

### 2. Context function tests
- Happy path
- Error paths (every `{:error, _}` return)
- **Tenant isolation** — org A cannot access org B's data
- Edge cases (empty input, nil, boundary values)

### 3. RBAC tests (for admin features)
- Authorized role → action succeeds
- Unauthorized role → action denied
- Cross-org user → action denied

### 4. LiveView pathway tests (for EVERY user-facing feature)
- **Every possible user pathway through the feature** (see "The E2E Rule")
- Page renders with expected elements
- Every `handle_event` produces the correct outcome
- Every conditional render is tested in both states
- Form validation errors render correctly
- Flash messages appear for success and error
- Subscription gating redirects unauthenticated/unsubscribed viewers
- Multi-tenant isolation — other org's data never appears

### 5. Wallaby E2E tests (ONLY for JS-dependent features)
- Tagged with `@moduletag :e2e`
- Only for: TypeScript hooks, drag-and-drop, Stripe redirects, visual rendering
- NOT for anything LiveViewTest can cover

### 6. Oban worker tests
- Happy path processing
- Idempotency (running twice produces same result)
- Error handling (malformed payload, missing records)

---

## Running Tests

```bash
# Run all tests except E2E (default for development)
mix test

# Run with coverage
mix test --cover

# Run a specific file
mix test test/bobine/content/content_test.exs

# Run a specific test by line number
mix test test/bobine/content/content_test.exs:42

# Run only E2E tests (requires Chrome + ChromeDriver)
mix test --only e2e

# Run everything including E2E
mix test --include e2e
```

### CI requirements

All of the following must pass before deploy:
- `mix test --exclude e2e` — all unit and integration tests green
- `mix test --only e2e` — all Wallaby E2E tests green (separate CI job)
- `mix compile --warnings-as-errors` — no compiler warnings
- `mix format --check-formatted` — code is formatted
- `mix credo --strict` — no credo violations
- `mix dialyzer` — no dialyzer warnings
- `npx tsc --noEmit` — TypeScript type checks pass