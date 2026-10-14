# 16 · Your trial and Marquee billing

**Target length:** 2:00
**Audience:** owner
**Pages:** `/admin`, `/admin/settings/billing`
**Prerequisites:** trial org (banner visible); platform plans configured in
super admin so the plan grid is not empty; Stripe test mode.

## Scene 1 — What the trial includes (0:00–0:35)

**STAGE:** `/admin` with the banner "Free trial — **N** days left." and its
**Add payment** link in frame. Cut to `/admin/content`, "Upload Video" sheet,
then the flash "You've reached your plan's 5.0h of video. Upgrade in Billing
to add more." (stage it on an org at the cap, or use a still).

**VO:** Your trial runs thirty days with no card on file. It includes five
hours of video, ten viewers, full branding, and one admin seat. The only
thing it leaves out is a custom domain. Hit a limit and the app tells you
where to upgrade.

## Scene 2 — Billing page (0:35–1:20)

**STAGE:** Click **Add payment** (or sidebar **Billing**). `/admin/settings/billing`,
header "Billing", "Choose a plan" grid: plan cards with name, price per month,
description, limits ("N videos", "N views/mo", "N team seats" or
"Unlimited …"), a "Popular" pill on one, and **Subscribe** buttons. Click
Subscribe; cut to Stripe Checkout; cut back to the page now showing "Current
plan" badge, the plan name, **Change plan** and **Manage subscription**, and
three usage meters: Videos, "Monthly views", "Team members".

**VO:** Billing is where you pay Marquee, separate from Stripe Connect,
which is how your viewers pay you. Pick a plan, check out, and the page
switches to your current plan with usage meters against its limits. Manage
subscription opens the Stripe portal for invoices and cards; Change plan
brings the grid back.

## Scene 3 — What happens if you don't (1:20–1:45)

**STAGE:** Still or staged shot of the red banner "Your free trial has ended.
Add a payment method to keep publishing." Then the viewer site playing a
video normally.

**VO:** If the trial ends without a plan, the admin is soft-locked: you can
look but not publish. Your viewers are not affected; everything already live
keeps playing. Add a payment method and the lock lifts.

## Scene 4 — Close (1:45–2:00)

**STAGE:** `/admin/settings/billing` with the current plan.

**VO:** That's the series. Everything here is repeatable from the "Take a
tour" link and these videos, whenever you need a refresher.

## Rough edges

- A "Payment overdue" banner with "Update payment method" appears for past-due
  platform subscriptions. Out of scope.
- Custom domains are set by Marquee staff, not from this admin. Do not
  promise a self-service field.
