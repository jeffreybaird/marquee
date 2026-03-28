# Stripe Integration

Load this file when working on subscriptions, plans, checkout, or Stripe webhook
processing.

---

## Client Architecture

### Single entry point: `Bobine.Billing.StripeClient`

All Stripe API calls go through this module. No other module in the codebase may
call the Stripe library directly.

```elixir
defmodule Bobine.Billing.StripeClient do
  @behaviour Bobine.Billing.StripeClientBehaviour

  @impl true
  def create_customer(params), do: ...

  @impl true
  def create_subscription(customer_id, price_id), do: ...

  @impl true
  def cancel_subscription(stripe_subscription_id), do: ...

  @impl true
  def create_checkout_session(params), do: ...

  @impl true
  def create_billing_portal_session(customer_id, return_url), do: ...
end
```

### Behaviour for testability

```elixir
defmodule Bobine.Billing.StripeClientBehaviour do
  @callback create_customer(map()) :: {:ok, map()} | {:error, term()}
  @callback create_subscription(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback cancel_subscription(String.t()) :: {:ok, map()} | {:error, term()}
  @callback create_checkout_session(map()) :: {:ok, map()} | {:error, term()}
  @callback create_billing_portal_session(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
end
```

### Accessing the client

```elixir
defp stripe_client do
  Application.get_env(:stream_vane, :stripe_client, Bobine.Billing.StripeClient)
end
```

---

## Data Model

### Per-tenant billing isolation

Each organization has its own Stripe products, prices, and customer records.
A viewer subscribing to Org A has no relationship to Org B's Stripe account.

### Key schemas

| Schema         | Purpose                                               |
|----------------|-------------------------------------------------------|
| `Plan`         | An org's subscription tier (name, Stripe price ID, amount, interval) |
| `Subscription` | A viewer's active subscription to an org's plan       |

### Stripe identifiers stored locally

| Field                      | On Schema      | Purpose                           |
|----------------------------|----------------|-----------------------------------|
| `stripe_customer_id`       | `User`         | The viewer's Stripe customer ID   |
| `stripe_price_id`          | `Plan`         | The Stripe price object ID        |
| `stripe_product_id`        | `Plan`         | The Stripe product object ID      |
| `stripe_subscription_id`   | `Subscription` | The Stripe subscription object ID |
| `stripe_account_id`        | `Organization` | Connect account ID (future, for payouts) |

---

## Subscription Flow (SVOD)

### Checkout

1. Viewer clicks "Subscribe" on the org's viewer site
2. Backend creates a Stripe Checkout Session via `StripeClient`
3. Viewer is redirected to Stripe's hosted checkout page
4. On success, Stripe redirects back to the org's site
5. Stripe sends `checkout.session.completed` webhook
6. The `StripeWebhookProcessor` Oban worker creates the local `Subscription` record

### Cancellation

1. Viewer clicks "Manage Subscription" → redirected to Stripe Billing Portal
2. Or: viewer cancels through the org's account page
3. Backend calls `StripeClient.cancel_subscription/1`
4. Stripe sends `customer.subscription.updated` webhook with `cancel_at_period_end`
5. Worker updates local subscription status

### Subscription gating

The `RequireSubscription` plug checks whether the current viewer has an active
subscription to the current organization. If not, they are redirected to the
org's pricing/signup page.

```elixir
# Only applied to viewer routes that require a subscription
pipe_through [:browser, :require_auth, :set_organization, :require_subscription]
```

---

## Webhook Processing

### Inbound endpoint: `/webhooks/stripe`

```elixir
scope "/webhooks" do
  pipe_through :webhook
  post "/stripe", WebhookController, :stripe
end
```

### Signature verification

Every inbound Stripe webhook must be verified using `Stripe.Webhook.construct_event/3`
before processing. Reject unverified payloads with a `400` response.

### Async processing via Oban

Same pattern as Mux — verify signature, enqueue Oban job, respond `200`
immediately.

### Key webhook events to handle

| Stripe Event                          | Action                                    |
|---------------------------------------|-------------------------------------------|
| `checkout.session.completed`          | Create local subscription record          |
| `customer.subscription.updated`       | Sync status (active, past_due, canceled)  |
| `customer.subscription.deleted`       | Mark subscription as canceled             |
| `invoice.payment_succeeded`           | Update billing status, extend access      |
| `invoice.payment_failed`              | Mark subscription as past_due, notify org |

### Idempotency

Use the Stripe event ID as an Oban unique key. Processing the same event twice
must produce the same result.

---

## Environment Variables

| Variable                | Required | Purpose                          |
|-------------------------|----------|----------------------------------|
| `STRIPE_SECRET_KEY`     | Yes      | Stripe API secret key            |
| `STRIPE_WEBHOOK_SECRET` | Yes      | Webhook signature verification   |

These live in Fly secrets and GitHub Actions secrets. Never in source code.

---

## Future: Multi-tenant Stripe Connect

The current MVP uses a single Stripe account (Bobine's). When we add
Stripe Connect, each organization will have their own connected account, and
subscription payments will flow through Connect with platform fees. The
`stripe_account_id` field on `Organization` is reserved for this purpose.

Do not build Connect integration yet — but do not make architectural decisions
that would prevent it. Specifically:

- Always associate Stripe objects with both the organization and the viewer
- Never hardcode a single Stripe account assumption in the billing context
- Keep the `StripeClient` methods flexible enough to accept an optional
  `stripe_account` header for Connect

---

## Testing Stripe Features

Use `Mox` to mock the `StripeClientBehaviour`. Never make real Stripe API calls
in tests.

```elixir
import Mox

setup :verify_on_exit!

test "creates a checkout session for the viewer" do
  org = insert(:organization)
  user = insert(:user)
  plan = insert(:plan, organization: org)

  expect(MockStripeClient, :create_checkout_session, fn params ->
    assert params.price_id == plan.stripe_price_id
    {:ok, %{id: "cs_test_123", url: "https://checkout.stripe.com/test"}}
  end)

  assert {:ok, session} = Billing.create_checkout(org, user, plan)
  assert session.url =~ "checkout.stripe.com"
end
```

For webhook processing tests, build the Stripe event payload manually and
pass it directly to the Oban worker's `perform/1` function.
