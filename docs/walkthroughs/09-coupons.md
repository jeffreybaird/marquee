# 09 · Coupons

**Target length:** 2:00
**Audience:** owner or admin
**Pages:** `/admin/coupons`, Stripe Checkout
**Prerequisites:** Stripe connected, one active plan, viewer profile with no
subscription.

## Scene 1 — Where coupons live (0:00–0:15)

**STAGE:** Type `/admin/coupons` into the address bar (there is no sidebar
link). Panel "Coupons", subtitle "Stripe-backed discount codes for viewer
subscriptions." Empty state "No coupons yet".

**VO:** Coupons are discount codes viewers type in at checkout. They're
created here and stored in Stripe, so they work anywhere Stripe Checkout
does.

## Scene 2 — Create one (0:15–1:05)

**STAGE:** Click the new coupon button. Sheet "New coupon", subtitle "Syncs to
Stripe on save." Code "LAUNCH50" (renders uppercase), Name "Launch discount".
"Discount type": click **Percent off**, enter 50 in "Percent off". Click
**Amount off** to show "Amount off (dollars)", then back to Percent off.
Duration select: Once, Repeating, Forever; pick Repeating and set "Duration in
months (for repeating)" to 3. Save. Flash "Coupon created." The coupon appears
in the list.

**VO:** Code is what viewers type. Name is for you. Pick a percentage or a
fixed dollar amount off. Duration decides how long it applies: once, for a
set number of months, or forever. Save, and it's live in Stripe.

## Scene 3 — At checkout (1:05–1:40)

**STAGE:** Viewer profile: `/subscribe`, click **Subscribe** or **Start free
trial**. In Stripe Checkout, open the promotion code field, type LAUNCH50, show
the discounted total. Cancel out (or complete in test mode).

**VO:** At checkout the viewer enters the code and the total updates before
they pay. Invalid or expired codes are rejected by Stripe with a clear
message.

## Scene 4 — Deactivate (1:40–2:00)

**STAGE:** Back on `/admin/coupons`, click **Deactivate** on the coupon. Flash
"Coupon deactivated."

**VO:** When a promotion ends, deactivate the code. Anyone already using it
keeps their discount for its duration; new checkouts can't apply it.

## Rough edges

- No sidebar link; the address bar is on screen for this script, so record
  on a hostname-resolved environment or crop.
