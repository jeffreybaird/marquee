# Task: Feature 05b — Platform Billing (Org Subscribes to Bobine)

This feature handles how organizations pay Bobine for platform access. It's
a standard Stripe Subscription against Bobine's own Stripe account — no
Connect involved. The plan determines the org's usage limits and feature
access via the feature flags system.

Follow all rules in CLAUDE.md. Load `.claude/stripe-integration.md`,
`.claude/architecture-decisions.md`, `.claude/observability.md`, and
`.claude/testing.md`.

This task has 7 parts. Do them in order. Run `mix test` after each part.

---

## Part 1: Plan Structure — The 3×3 Grid

### Two axes

**Usage tier** — gates infrastructure capacity (storage, streaming, encoding):
- `basic` — small catalog, modest viewership
- `super` — medium catalog, growing audience
- `premium` — large catalog, high-volume streaming

**Business tier** — gates features, team size, and support:
- `individual` — solo creator, base features
- `small_business` — small team, expanded features
- `enterprise` — full team, all features, priority support

### The 9 plans

| Plan | Usage | Business | Key limits |
|---|---|---|---|
| `individual_basic` | basic | individual | 50 videos, 5K views/mo, 1 team seat |
| `individual_super` | super | individual | 500 videos, 50K views/mo, 1 team seat |
| `individual_premium` | premium | individual | 2K videos, 200K views/mo, 1 team seat |
| `small_business_basic` | basic | small_business | 50 videos, 5K views/mo, 5 team seats |
| `small_business_super` | super | small_business | 500 videos, 50K views/mo, 5 team seats |
| `small_business_premium` | premium | small_business | 2K videos, 200K views/mo, 10 team seats |
| `enterprise_basic` | basic | enterprise | 200 videos, 20K views/mo, unlimited seats |
| `enterprise_super` | super | enterprise | 2K videos, 200K views/mo, unlimited seats |
| `enterprise_premium` | premium | enterprise | unlimited videos, unlimited views, unlimited seats |

These limits are illustrative — the actual numbers and prices will be
configured by Bobine admins. The important thing is the schema supports
them and the enforcement layer reads from the plan configuration.

### Feature access by business tier

| Feature | individual | small_business | enterprise |
|---|---|---|---|
| Custom domain | no | yes | yes |
| AI recommendation rows | no | no | yes |
| Advanced DRM | no | yes | yes |
| Live streaming | no | no | yes |
| Priority support | no | no | yes |
| API access | no | yes | yes |
| Custom email domain | no | no | yes |
| White-label (no Bobine branding in footer) | no | no | yes |
| Webhook endpoints | 1 | 5 | unlimited |
| Analytics export | basic | full | full + API |

---

## Part 2: Platform Plan Schema

### Schema: `PlatformPlan`

This should already exist from initial scaffolding. Verify or update:

```elixir
schema "platform_plans" do
  field :name, :string                     # "Individual Basic", "Enterprise Premium"
  field :slug, :string                     # "individual_basic", "enterprise_premium"
  field :stripe_product_id, :string        # Stripe Product ID on Bobine's account
  field :stripe_price_id, :string          # Stripe Price ID on Bobine's account

  # Pricing
  field :amount, :integer                  # Monthly price in cents
  field :currency, :string, default: "usd"
  field :interval, Ecto.Enum, values: [:monthly, :yearly], default: :monthly

  # Tier classification
  field :usage_tier, Ecto.Enum, values: [:basic, :super, :premium]
  field :business_tier, Ecto.Enum, values: [:individual, :small_business, :enterprise]

  # Usage limits
  field :max_videos, :integer              # nil = unlimited
  field :max_monthly_views, :integer       # nil = unlimited
  field :max_storage_gb, :integer          # nil = unlimited
  field :max_team_seats, :integer          # nil = unlimited
  field :max_webhook_endpoints, :integer   # nil = unlimited

  # Feature flags this plan enables
  field :enabled_features, {:array, :string}, default: []
  # e.g. ["custom_domain", "advanced_drm", "live_streaming", "api_access"]

  # Display
  field :description, :string
  field :highlight, :boolean, default: false  # "Most popular" badge
  field :position, :integer, default: 0
  field :active, :boolean, default: true

  field :deleted_at, :utc_datetime

  timestamps(type: :utc_datetime)
end
```

Migration:
- Unique index on `[:slug]`
- Unique index on `[:usage_tier, :business_tier]` (one plan per grid cell)
- Index on `[:active]`

### Important: these are Bobine-level records, NOT tenant-scoped

Platform plans have NO `organization_id`. They are global records managed by
super admins. Every org sees the same plan options.

---

## Part 3: Platform Subscription Schema

### Schema: `PlatformSubscription`

```elixir
schema "platform_subscriptions" do
  belongs_to :organization, Organization
  belongs_to :platform_plan, PlatformPlan

  field :stripe_subscription_id, :string
  field :stripe_customer_id, :string       # Stripe Customer for the org on Bobine's account
  field :status, :string                   # "active", "trialing", "past_due", "canceled", "unpaid"
  field :current_period_start, :utc_datetime
  field :current_period_end, :utc_datetime
  field :trial_start, :utc_datetime
  field :trial_end, :utc_datetime
  field :canceled_at, :utc_datetime
  field :cancel_at_period_end, :boolean, default: false

  timestamps(type: :utc_datetime)
end
```

Migration:
- Unique index on `[:organization_id]` — one active subscription per org
- Unique index on `[:stripe_subscription_id]`
- Index on `[:status]`

---

## Part 4: Platform Billing Context

Create `Bobine.PlatformBilling` (or add to a `Bobine.Admin.Billing` namespace)
to keep it separate from the viewer billing in `Bobine.Billing`:

### Plan management (super admin)

```elixir
def list_platform_plans(opts \\ [])
def get_platform_plan(id)
def get_platform_plan!(id)
def get_platform_plan_by_slug(slug)

def create_platform_plan(attrs)   # Creates Stripe Product + Price on Bobine's account
def update_platform_plan(plan, attrs)
def deactivate_platform_plan(plan)
```

These are super-admin-only functions. No scope parameter — they operate at
the platform level.

### Org subscription management

```elixir
@doc "Gets the org's current platform subscription."
def get_subscription(organization)

@doc "Creates a checkout session for an org to subscribe to a platform plan."
def create_org_checkout(organization, platform_plan, user) do
  # This hits Bobine's own Stripe account (NOT Connect)
  # user is the operator initiating the checkout

  Telemetry.with_span "bobine.platform_billing.create_checkout",
    %{"bobine.org.id" => organization.id} do

    params = %{
      mode: "subscription",
      line_items: [%{price: platform_plan.stripe_price_id, quantity: 1}],
      success_url: "#{base_url()}/admin/settings/billing/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "#{base_url()}/admin/settings/billing",
      customer_email: user.email,
      metadata: %{
        organization_id: organization.id,
        platform_plan_id: platform_plan.id
      }
    }

    # This does NOT use Connect — it's a direct charge to Bobine's account
    stripe_client().create_checkout_session(params)
  end
end

@doc "Creates a portal session for an org to manage their platform subscription."
def create_org_portal_session(organization)

@doc "Changes an org's plan (upgrade or downgrade)."
def change_plan(organization, new_platform_plan)

@doc "Cancels an org's platform subscription."
def cancel_subscription(organization)
```

### Feature flag syncing

When an org's subscription activates or changes, sync their feature flags
to match the new plan:

```elixir
def sync_features_to_plan(organization, platform_plan) do
  features =
    platform_plan.enabled_features
    |> Enum.map(fn feature -> {feature, true} end)
    |> Map.new()

  organization
  |> Organization.changeset(%{features: features})
  |> Repo.update()
end
```

This is the bridge between billing and feature access. When an org upgrades
from `individual_basic` to `small_business_super`, their feature flags
update immediately:

```elixir
# individual_basic features:
%{}

# small_business_super features:
%{
  "custom_domain" => true,
  "advanced_drm" => true,
  "api_access" => true,
  "analytics_export_full" => true
}
```

### Usage limit enforcement

Create `Bobine.PlatformBilling.UsageLimits`:

```elixir
defmodule Bobine.PlatformBilling.UsageLimits do
  @doc """
  Checks if the org can perform an action given their plan limits.

      iex> can_upload_video?(org_on_basic_with_49_videos)
      true

      iex> can_upload_video?(org_on_basic_with_50_videos)
      false
  """
  def can_upload_video?(organization) do
    plan = get_plan_for_org(organization)
    case plan.max_videos do
      nil -> true
      limit ->
        current = Content.count_videos(organization)
        current < limit
    end
  end

  def can_add_team_member?(organization) do
    plan = get_plan_for_org(organization)
    case plan.max_team_seats do
      nil -> true
      limit ->
        current = Accounts.count_memberships(organization)
        current < limit
    end
  end

  def can_add_webhook_endpoint?(organization) do
    plan = get_plan_for_org(organization)
    case plan.max_webhook_endpoints do
      nil -> true
      limit ->
        current = Webhooks.count_endpoints(organization)
        current < limit
    end
  end

  def video_limit_status(organization) do
    plan = get_plan_for_org(organization)
    current = Content.count_videos(organization)
    %{current: current, limit: plan.max_videos, reached: plan.max_videos && current >= plan.max_videos}
  end

  defp get_plan_for_org(organization) do
    case PlatformBilling.get_subscription(organization) do
      {:ok, sub} -> PlatformBilling.get_platform_plan!(sub.platform_plan_id)
      _ -> default_free_limits()
    end
  end

  defp default_free_limits do
    # Orgs without a subscription get minimal limits (or no access)
    %{max_videos: 5, max_monthly_views: 500, max_team_seats: 1,
      max_webhook_endpoints: 0, enabled_features: []}
  end
end
```

### Enforce limits in context functions

Update the content and accounts contexts to check limits before mutations:

```elixir
# In Content context
def create_video(scope, attrs) do
  unless UsageLimits.can_upload_video?(scope.organization) do
    limit_status = UsageLimits.video_limit_status(scope.organization)
    {:error, :plan_limit_reached, limit_status}
  else
    # ... existing create logic
  end
end

# In Accounts context
def create_membership(scope, attrs) do
  unless UsageLimits.can_add_team_member?(scope.organization) do
    {:error, :plan_limit_reached, %{resource: "team_seats"}}
  else
    # ... existing create logic
  end
end
```

---

## Part 5: Platform Webhook Processing

Platform subscription webhooks come to the same `/webhooks/stripe` endpoint
but WITHOUT a `Stripe-Account` header (they're direct events on Bobine's
account, not connected account events).

### Update StripeWebhookProcessor

Add handlers for platform events. Distinguish from connected account events
by checking for the presence of the connected account ID:

```elixir
# Connected account event (viewer subscription) — existing handlers
defp handle_event(type, data, connect_account_id) when not is_nil(connect_account_id) do
  # ... existing Feature 05a handlers
end

# Platform event (org subscription) — new handlers
defp handle_event("checkout.session.completed", session, nil) do
  # Platform checkout — org subscribing to Bobine
  org_id = session["metadata"]["organization_id"]
  plan_id = session["metadata"]["platform_plan_id"]

  with {:ok, org} <- Accounts.get_organization(org_id),
       {:ok, plan} <- PlatformBilling.get_platform_plan(plan_id),
       {:ok, sub} <- PlatformBilling.create_subscription_from_checkout(org, plan, session) do
    PlatformBilling.sync_features_to_plan(org, plan)
    Events.broadcast_global({:platform_subscription_created, org, plan})
    :ok
  end
end

defp handle_event("customer.subscription.updated", subscription_data, nil) do
  case PlatformBilling.get_subscription_by_stripe_id(subscription_data["id"]) do
    {:ok, sub} ->
      PlatformBilling.update_subscription_from_stripe(sub, subscription_data)
      # If plan changed, sync features
      if plan_changed?(sub, subscription_data) do
        org = Accounts.get_organization!(sub.organization_id)
        new_plan = PlatformBilling.get_platform_plan!(sub.platform_plan_id)
        PlatformBilling.sync_features_to_plan(org, new_plan)
      end
      :ok

    {:error, :not_found} ->
      Logger.warning("Platform subscription not found", stripe_id: subscription_data["id"])
      :ok
  end
end

defp handle_event("customer.subscription.deleted", subscription_data, nil) do
  case PlatformBilling.get_subscription_by_stripe_id(subscription_data["id"]) do
    {:ok, sub} ->
      org = Accounts.get_organization!(sub.organization_id)
      PlatformBilling.cancel_subscription_from_stripe(sub)
      # Remove feature flags — downgrade to free/default limits
      PlatformBilling.sync_features_to_plan(org, default_free_plan())
      :ok

    {:error, :not_found} -> :ok
  end
end

defp handle_event("invoice.payment_failed", invoice, nil) do
  # Platform payment failed — org's access at risk
  with {:ok, sub} <- PlatformBilling.get_subscription_by_stripe_id(invoice["subscription"]) do
    PlatformBilling.mark_platform_payment_failed(sub)
    # Don't immediately kill the org's platform — grace period
    # But show a warning banner in the admin dashboard
    :ok
  end
end

defp handle_event("invoice.payment_succeeded", invoice, nil) do
  with {:ok, sub} <- PlatformBilling.get_subscription_by_stripe_id(invoice["subscription"]) do
    PlatformBilling.mark_platform_payment_succeeded(sub)
    :ok
  end
end
```

### Platform dunning — different from viewer dunning

When an org's payment fails, you do NOT immediately kill their platform.
Their viewers are paying customers who would lose access. Instead:

1. Show a warning banner in the admin dashboard: "Your Bobine payment is
   overdue. Update your payment method to avoid service interruption."
2. Stripe retries automatically over ~3 weeks
3. If all retries fail and the subscription is canceled:
   - Downgrade the org to free/default limits
   - Disable premium features (sync feature flags)
   - Do NOT delete their data or stop their viewers' subscriptions
   - Show an urgent banner: "Your Bobine subscription has been canceled.
     Subscribe to restore full access."
4. Viewers continue to have access to already-published content (the org
   paid for it). The org just can't upload new videos or use gated features.

This is more forgiving than viewer dunning because the blast radius is
larger — an org going dark affects all their viewers.

---

## Part 6: Admin UI for Platform Billing

### Operator billing page (`/admin/settings/billing`)

**No subscription:**
- Plan selection grid showing all 9 plans
- Grid layout: usage tier on one axis, business tier on the other
- Each plan card shows: name, price, key limits, feature list
- Current selection highlighted
- "Subscribe" button → Stripe Checkout on Bobine's account

**Active subscription:**
- Current plan highlighted with "Current plan" badge
- Usage dashboard: videos used / limit, views this month / limit, team seats / limit
- "Manage subscription" → Stripe Customer Portal
- "Change plan" → shows plan grid with upgrade/downgrade options
- Upgrade: immediately moves to new plan (prorated by Stripe)
- Downgrade: takes effect at end of billing period

**Past due:**
- Warning banner at top of admin dashboard (not just billing page)
- "Update payment method" button

**Canceled:**
- Plan grid with "Resubscribe" option
- Current limits shown (free/default)
- Features that were disabled are grayed out

### Super admin plan management (`/super/plans`)

Create a new super admin page for managing the 9 platform plans:

- Grid view showing all plans with current prices
- Click a plan to edit: name, description, amount, limits, feature list
- Create new plan (if expanding beyond the 3×3)
- Deactivate plan
- Price change warning (creates new Stripe Price)

### Usage dashboard component

A reusable component showing the org's usage vs limits:

```heex
<.usage_meter
  label="Videos"
  current={@usage.videos_current}
  limit={@usage.videos_limit}
/>
<.usage_meter
  label="Monthly views"
  current={@usage.views_current}
  limit={@usage.views_limit}
/>
<.usage_meter
  label="Team members"
  current={@usage.seats_current}
  limit={@usage.seats_limit}
/>
```

Show this on the admin dashboard (not just the billing page) so operators
always know where they stand.

### `data-test` attributes

- `data-test="platform-plan-grid"`
- `data-test={"platform-plan-#{slug}"}`
- `data-test="current-plan-badge"`
- `data-test="subscribe-btn"`
- `data-test="change-plan-btn"`
- `data-test="manage-subscription-btn"`
- `data-test="billing-warning-banner"`
- `data-test="usage-meter-videos"`
- `data-test="usage-meter-views"`
- `data-test="usage-meter-seats"`

---

## Part 7: Tests

### Schema tests

- PlatformPlan changeset with valid attrs
- Unique constraint on `[usage_tier, business_tier]`
- Unique constraint on `slug`
- PlatformSubscription changeset with valid attrs
- Unique constraint on `[organization_id]`

### Context tests

**`test/bobine/platform_billing/platform_billing_test.exs`**

Plan management:
- `list_platform_plans/1` returns all active plans
- `get_platform_plan_by_slug/1` returns correct plan
- `create_platform_plan/1` creates Stripe Product + Price (mock)
- `deactivate_platform_plan/1` hides from selection

Subscription:
- `create_org_checkout/3` returns Stripe Checkout Session (mock)
- `create_org_checkout/3` uses Bobine's Stripe account (NOT Connect)
- `create_subscription_from_checkout/3` creates PlatformSubscription
- `get_subscription/1` returns org's active subscription
- `change_plan/2` updates subscription to new plan
- `cancel_subscription_from_stripe/1` marks as canceled

Feature syncing:
- `sync_features_to_plan/2` sets org's feature flags from plan's enabled_features
- Upgrading plan adds new feature flags
- Downgrading plan removes feature flags
- Canceling subscription clears feature flags to default

**`test/bobine/platform_billing/usage_limits_test.exs`**

- `can_upload_video?/1` returns true when under limit
- `can_upload_video?/1` returns false when at limit
- `can_upload_video?/1` returns true when limit is nil (unlimited)
- `can_add_team_member?/1` respects seat limits
- `can_add_webhook_endpoint?/1` respects endpoint limits
- `video_limit_status/1` returns current count and limit
- Org with no subscription gets default free limits

**`test/bobine/platform_billing/enforcement_test.exs`**

These test that limits are actually enforced in the context functions:

- `Content.create_video/2` returns `{:error, :plan_limit_reached, _}` when at video limit
- `Accounts.create_membership/2` returns error when at seat limit
- `Webhooks.create_endpoint/2` returns error when at endpoint limit
- After upgrading plan, previously-blocked action succeeds
- After downgrading plan, action that was within old limit but exceeds new limit is blocked

### Webhook processor tests

**`test/bobine/workers/stripe_webhook_processor_platform_test.exs`**

- Platform `checkout.session.completed` creates subscription and syncs features
- Platform `customer.subscription.updated` syncs features on plan change
- Platform `customer.subscription.deleted` clears features to defaults
- Platform `invoice.payment_failed` marks subscription as past_due
- Platform `invoice.payment_succeeded` restores status
- Platform events (no connect account) don't trigger viewer billing handlers
- Viewer events (with connect account) don't trigger platform handlers

### Lifecycle tests

```elixir
describe "platform subscription lifecycle" do
  test "org subscribes to small_business_super, upgrades to enterprise_premium, cancels" do
    org = insert(:organization)
    sb_super = insert(:platform_plan, slug: "small_business_super",
      usage_tier: :super, business_tier: :small_business,
      enabled_features: ["custom_domain", "advanced_drm", "api_access"])
    ent_premium = insert(:platform_plan, slug: "enterprise_premium",
      usage_tier: :premium, business_tier: :enterprise,
      enabled_features: ["custom_domain", "advanced_drm", "api_access",
        "live_streaming", "ai_recommendations", "priority_support",
        "custom_email_domain", "white_label"])

    # 1. Subscribe to small_business_super
    checkout_event = build_platform_stripe_event("checkout.session.completed", %{
      "metadata" => %{"organization_id" => org.id, "platform_plan_id" => sb_super.id}
    })
    assert :ok = perform_job(StripeWebhookProcessor, %{"event" => checkout_event})

    org = Accounts.get_organization!(org.id)
    assert org.features["custom_domain"] == true
    assert org.features["advanced_drm"] == true
    assert org.features["live_streaming"] != true  # not on this plan

    # 2. Upgrade to enterprise_premium
    update_event = build_platform_stripe_event("customer.subscription.updated", %{...})
    assert :ok = perform_job(StripeWebhookProcessor, %{"event" => update_event})

    org = Accounts.get_organization!(org.id)
    assert org.features["live_streaming"] == true
    assert org.features["ai_recommendations"] == true

    # 3. Cancel
    deleted_event = build_platform_stripe_event("customer.subscription.deleted", %{...})
    assert :ok = perform_job(StripeWebhookProcessor, %{"event" => deleted_event})

    org = Accounts.get_organization!(org.id)
    assert org.features == %{}  # all features removed
  end
end
```

### LiveView tests

**`test/bobine_web/live/admin/billing_live_test.exs`**

- Plan grid shows all 9 active plans
- Current plan is highlighted when org has subscription
- Subscribe button creates checkout session (mock)
- Usage meters show correct values
- Past due banner visible when payment failed
- Change plan shows upgrade/downgrade options
- "Manage subscription" creates portal session (mock)

**`test/bobine_web/live/super/plans_live_test.exs`**

- Lists all platform plans
- Edit plan updates fields
- Price change creates new Stripe Price (mock)
- Only super admins can access

### Limit enforcement in UI

- Upload video button disabled or shows upgrade prompt when at limit
- Add team member shows upgrade prompt when at seat limit
- Plan limits visible in the billing dashboard
- Feature-gated UI elements hidden when feature flag is off

---

## Seed Data

Update `priv/repo/seeds.exs` to create all 9 platform plans with
realistic limits and pricing. These are created without Stripe
Product/Price IDs in dev (those only exist when connected to Stripe):

```elixir
platform_plans = [
  %{slug: "individual_basic", name: "Individual Basic",
    usage_tier: :basic, business_tier: :individual,
    amount: 2900, max_videos: 50, max_monthly_views: 5_000,
    max_team_seats: 1, max_webhook_endpoints: 1,
    enabled_features: []},

  %{slug: "individual_super", name: "Individual Super",
    usage_tier: :super, business_tier: :individual,
    amount: 7900, max_videos: 500, max_monthly_views: 50_000,
    max_team_seats: 1, max_webhook_endpoints: 1,
    enabled_features: []},

  # ... remaining 7 plans
]
```

---

## Definition of Done

- [ ] `PlatformPlan` schema with usage tier, business tier, limits, and feature list
- [ ] All 9 plans seeded with realistic limits and pricing
- [ ] `PlatformSubscription` schema tracking org's Bobine subscription
- [ ] `PlatformBilling` context with checkout, portal, plan change, cancellation
- [ ] Checkout creates session on Bobine's Stripe account (NOT Connect)
- [ ] Feature flag syncing: plan change → org features updated immediately
- [ ] Feature flags cleared on subscription cancellation
- [ ] `UsageLimits` module checking video, seat, and endpoint limits
- [ ] Limits enforced in `Content.create_video`, `Accounts.create_membership`, etc.
- [ ] Limit-reached returns `{:error, :plan_limit_reached, details}`
- [ ] Platform webhook handlers separate from connected account handlers
- [ ] Platform dunning: warning banner, no immediate org shutdown
- [ ] Platform cancellation: downgrade to free limits, data preserved
- [ ] Billing page in admin settings with plan grid
- [ ] Usage dashboard with meters for videos, views, seats
- [ ] Super admin plan management page
- [ ] Full lifecycle test: subscribe → upgrade → cancel → features update
- [ ] Enforcement test: limit reached → blocked → upgrade → unblocked
- [ ] Webhook processing tests for all platform event types
- [ ] Platform events and connected account events correctly routed
- [ ] All context functions have OTel spans
- [ ] All Stripe calls have idempotency keys
- [ ] Audit logging on all subscription changes
- [ ] `export_organization_data/1` updated with platform subscription
- [ ] `data-test` attributes on all interactive elements
- [ ] `mix format`, `mix credo --strict`, `mix dialyzer` pass