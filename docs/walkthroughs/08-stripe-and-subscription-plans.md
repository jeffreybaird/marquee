# 08 · Stripe and subscription plans

**Target length:** 4:00
**Audience:** owner
**Pages:** `/admin/settings`, `/admin/plans`, the viewer site (`/subscribe`)
**Prerequisites:** Stripe test mode account; a second browser profile logged
in as a viewer with no subscription; the "Create a subscription plan" nudge
still on the dashboard.

## Scene 1 — Two halves of getting paid (0:00–0:20)

**STAGE:** `/admin`, setup nudges in frame: "Connect Stripe to accept
payments" and "Create a subscription plan".

**VO:** Getting paid takes two steps. Connect a Stripe account so money has
somewhere to go, then create at least one plan viewers can subscribe to.
Until both are done, every video on your site is behind a wall nobody can get
through.

## Scene 2 — Connect Stripe (0:20–1:10)

**STAGE:** Click **Set up payments** on the nudge (lands on `/admin/settings`).
Section "Payments": "Connect your Stripe account to accept viewer
subscriptions and receive payments." Click **Connect Stripe account**. Cut to
Stripe's hosted onboarding (blur any personal details), then cut back to
`/admin/settings` showing the green dot, "Stripe connected", "Account: acct_…"
and the "Manage in Stripe Dashboard" link.

**VO:** Settings, Payments, Connect Stripe account. Stripe walks you through
its own onboarding: business details, bank account, identity. When it sends
you back you'll see Stripe connected and your account ID. Payouts, refunds and
tax settings live in the Stripe dashboard; the link is right here.

## Scene 3 — Create a plan (1:10–2:20)

**STAGE:** Sidebar has no Plans link. Return to the dashboard and click **Add
a plan** on the "Create a subscription plan" nudge (lands on `/admin/plans`).
Panel "Plans", subtitle "Viewer subscription tiers backed by Stripe Connect.",
empty state "No plans yet". Click **New plan**. Sheet "New plan", subtitle
"Syncs to Stripe on save." Fill: Name "Monthly", Description one line, "Price
(dollars)" 9.99, Interval Monthly, "Trial period (days)" 7, "Features (one per
line)" three lines. Click **Save**. Flash "Plan created." Row shows "Monthly",
a "7-day trial" pill and "$9.99/monthly".

**VO:** Plans are reached from the dashboard nudge, or by going to slash admin
slash plans. New plan. Name, description, price, monthly or yearly, an
optional free trial in days, and a feature list, one per line, that shows on
the subscribe page. Save creates the product and price in Stripe for you.

## Scene 4 — Editing and retiring plans (2:20–2:50)

**STAGE:** Click **Edit** on the plan, change the price to 12.00; the warning
appears: "Changing the price will create a new Stripe Price. Existing
subscribers keep their current price." Cancel. Click **Deactivate**; flash
"Plan deactivated.", row dims with an "Inactive" pill. Click **Reactivate**.

**VO:** You can edit a plan later. Raising the price creates a new Stripe
price for new subscribers; existing ones keep what they signed up at.
Deactivate stops new signups without touching anyone already subscribed, and
Reactivate brings it back.

## Scene 5 — What the viewer sees (2:50–3:40)

**STAGE:** Switch to the viewer profile. Homepage, click any video card. The
app redirects to `/subscribe`: heading "Choose a plan", "Subscribe to <org
name>", the plan card with name, price, the feature list and a "7-day free
trial" note, and the button **Start free trial**. Click it; cut to Stripe
Checkout (test card), cut back to the success page, then the video playing.

**VO:** For a viewer, clicking any video before subscribing lands on Choose a
plan. They see your plans with the features you listed. Start free trial
opens Stripe Checkout; when it completes, they're back on your site and the
video plays. Coupons and cancellations also run through Stripe, and viewers
manage their own subscription from their account page.

## Scene 6 — Close (3:40–4:00)

**STAGE:** Back in the admin, dashboard. The two payment nudges are gone.
"Active Subscribers" KPI shows 1.

**VO:** Both setup tasks have cleared themselves, and you have your first
subscriber. Next: coupons.

## Rough edges

- If Stripe is not connected, `/admin/plans` shows "Connect your Stripe
  account in Settings before creating plans." and no New plan button.
- The "Start free trial" label appears only when the plan has trial days;
  otherwise the button reads "Subscribe".
- Blur the Stripe account ID in post if the account is real.
