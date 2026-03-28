# Testing

Load this file when writing tests, setting up test infrastructure, or reviewing
test coverage.

---

## Test Structure

```
test/
├── stream_vane/                          # Unit & context tests
│   ├── accounts/
│   │   ├── accounts_test.exs             # Context function tests
│   │   ├── organization_test.exs         # Schema/changeset tests
│   │   └── membership_test.exs
│   ├── content/
│   │   ├── content_test.exs
│   │   └── video_test.exs
│   ├── billing/
│   │   └── billing_test.exs
│   ├── engagement/
│   │   └── engagement_test.exs
│   ├── catalog/
│   │   └── catalog_test.exs
│   ├── analytics/
│   │   └── analytics_test.exs
│   ├── branding/
│   │   └── branding_test.exs
│   ├── webhooks/
│   │   └── webhooks_test.exs
│   └── workers/                          # Oban worker tests
│       ├── mux_webhook_processor_test.exs
│       ├── stripe_webhook_processor_test.exs
│       └── webhook_delivery_worker_test.exs
├── stream_vane_web/                      # Integration & LiveView tests
│   ├── live/
│   │   ├── admin/
│   │   │   ├── dashboard_live_test.exs
│   │   │   ├── content_live_test.exs
│   │   │   └── branding_live_test.exs
│   │   └── viewer/
│   │       ├── home_live_test.exs
│   │       ├── watch_live_test.exs
│   │       └── watchlist_live_test.exs
│   └── controllers/
│       └── webhook_controller_test.exs
├── support/
│   ├── conn_case.ex
│   ├── data_case.ex
│   ├── factory.ex                        # ExMachina factory
│   └── mocks.ex                          # Mox mock definitions
└── fixtures/
    └── mux_webhooks/                     # Sample Mux webhook payloads
        ├── asset_ready.json
        └── upload_asset_ready.json
```

---

## Test Foundations

### DataCase

All context/unit tests use `StreamVane.DataCase` which sets up the Ecto sandbox.

```elixir
defmodule StreamVane.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias StreamVane.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import StreamVane.DataCase
      import StreamVane.Factory
    end
  end

  setup tags do
    StreamVane.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(StreamVane.Repo, shared: not tags[:async])
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

Integration and LiveView tests use `StreamVane.ConnCase`.

```elixir
defmodule StreamVaneWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint StreamVaneWeb.Endpoint
      use StreamVaneWeb, :verified_routes
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import StreamVane.Factory
      import StreamVaneWeb.ConnCase
    end
  end

  setup tags do
    StreamVane.DataCase.setup_sandbox(tags)
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

  @doc "Builds an authenticated conn for a membership (creates user implicitly)."
  def conn_for(membership) do
    user = membership.user
    build_conn() |> authenticate(user, membership)
  end
end
```

---

## Factories (ExMachina)

Use `ExMachina` for test data. Every tenant-scoped factory must include an
`organization` association.

```elixir
defmodule StreamVane.Factory do
  use ExMachina.Ecto, repo: StreamVane.Repo

  def organization_factory do
    %StreamVane.Accounts.Organization{
      name: sequence(:name, &"Test Org #{&1}"),
      slug: sequence(:slug, &"test-org-#{&1}"),
    }
  end

  def user_factory do
    %StreamVane.Accounts.User{
      email: sequence(:email, &"user-#{&1}@example.com"),
      name: sequence(:name, &"User #{&1}"),
    }
  end

  def membership_factory do
    %StreamVane.Accounts.Membership{
      user: build(:user),
      organization: build(:organization),
      role: :editor,
    }
  end

  def video_factory do
    %StreamVane.Content.Video{
      organization: build(:organization),
      title: sequence(:title, &"Video #{&1}"),
      mux_asset_id: sequence(:mux_asset_id, &"asset_#{&1}"),
      mux_playback_id: sequence(:mux_playback_id, &"playback_#{&1}"),
      mux_status: "ready",
    }
  end

  def plan_factory do
    %StreamVane.Billing.Plan{
      organization: build(:organization),
      name: "Monthly",
      stripe_price_id: sequence(:stripe_price_id, &"price_#{&1}"),
      amount: 999,
      interval: :monthly,
    }
  end

  def subscription_factory do
    %StreamVane.Billing.Subscription{
      organization: build(:organization),
      user: build(:user),
      plan: build(:plan),
      stripe_subscription_id: sequence(:stripe_sub_id, &"sub_#{&1}"),
      status: :active,
    }
  end

  def theme_factory do
    %StreamVane.Branding.Theme{
      organization: build(:organization),
      brand_primary: "#1a73e8",
      brand_secondary: "#174ea6",
      background: "#0f0f0f",
      font_heading: "Inter",
      font_body: "Inter",
    }
  end
end
```

---

## Mocks (Mox)

### Setup

```elixir
# test/support/mocks.ex
Mox.defmock(StreamVane.Content.MockMuxClient,
  for: StreamVane.Content.MuxClientBehaviour)

Mox.defmock(StreamVane.Billing.MockStripeClient,
  for: StreamVane.Billing.StripeClientBehaviour)
```

```elixir
# config/test.exs
config :stream_vane, :mux_client, StreamVane.Content.MockMuxClient
config :stream_vane, :stripe_client, StreamVane.Billing.MockStripeClient
```

### Usage pattern

```elixir
import Mox

# In every test module that uses mocks
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
use Oban.Testing, repo: StreamVane.Repo

test "webhook controller enqueues processing job" do
  conn = build_conn()
  |> put_req_header("content-type", "application/json")
  |> post("/webhooks/mux", Jason.encode!(%{type: "video.asset.ready", ...}))

  assert response(conn, 200)
  assert_enqueued(worker: StreamVane.Workers.MuxWebhookProcessor)
end
```

---

## Required Test Categories

For every new feature, the following test types are required:

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

### 4. LiveView tests (for UI features)
- Page renders with expected elements
- User interactions trigger correct events
- Flash messages appear on success/error
- Subscription gating redirects unauthenticated viewers

### 5. Oban worker tests
- Happy path processing
- Idempotency (running twice produces same result)
- Error handling (malformed payload, missing records)

---

## Running Tests

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run a specific file
mix test test/stream_vane/content/content_test.exs

# Run a specific test by line number
mix test test/stream_vane/content/content_test.exs:42

# Run only tests tagged :focus (for development)
mix test --only focus
```

### CI requirements

All of the following must pass before deploy:
- `mix test` — all tests green
- `mix compile --warnings-as-errors` — no compiler warnings
- `mix format --check-formatted` — code is formatted
- `mix credo --strict` — no credo violations
- `mix dialyzer` — no dialyzer warnings
- `npx tsc --noEmit` — TypeScript type checks pass
