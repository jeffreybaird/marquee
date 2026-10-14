# 11 · Managing viewers

**Target length:** 2:30
**Audience:** owner or admin
**Pages:** `/admin/members`, the viewer site
**Prerequisites:** an org with several viewers (demo org or one with real
signups); at least one viewer subscribed.

## Scene 1 — The viewer list (0:00–0:30)

**STAGE:** `/admin/members`. Header "Members" with two tabs; the viewers tab
is active. Search box "Search by email or name...", a status filter with
Suspended and Banned options, and the table: Email, "Display Name",
Subscription, Status, Joined. Pagination at the bottom.

**VO:** Members lists everyone who has signed up to watch. Email, display
name, whether they're subscribed, their account status and when they joined.
Search by email or name, or filter to just suspended or banned accounts.

## Scene 2 — Suspend and reactivate (0:30–1:15)

**STAGE:** Search for a viewer. On their row click **Suspend**. Flash "Viewer
updated." Status changes to suspended. Filter by Suspended to show them alone.
Clear the filter, click **Reactivate**. Flash "Viewer updated."

**VO:** Suspend locks an account temporarily. The viewer can't log in or
watch, but nothing is deleted and their subscription stays where it is.
Reactivate reverses it. Use it for payment disputes or a cooling-off period.

## Scene 3 — Ban (1:15–1:35)

**STAGE:** On a different viewer click **Ban**. Confirm. Status shows banned.
Point at the Banned filter.

**VO:** Ban is permanent. The account is locked and stays that way. Reserve it
for abuse.

## Scene 4 — Grant access without a subscription (1:35–1:55)

**STAGE:** Find a viewer whose Subscription column is not active. Their row
shows a **Grant** button. Click it; flash "Viewer updated." and the button
becomes **Revoke**. Click **Revoke** to put it back.

**VO:** Grant gives a viewer full access without a paid subscription, for a
guest, a reviewer, or a comped account. Revoke takes it away again. It only
shows for viewers who aren't already subscribed.

## Scene 5 — See what they see (1:55–2:20)

**STAGE:** On an active subscribed viewer click **View as**. The viewer site
opens with a banner at the top: "You are impersonating <name>." and a **Stop
viewing** link. Scroll the homepage, open their watchlist. Click **Stop
viewing**; you're returned to `/admin/members`.

**VO:** When a viewer reports a problem, impersonate them. You're on the site
as that viewer, seeing their rows, their continue-watching, their watchlist.
Every action you take while impersonating is recorded in the audit log with
your name on it. Stop viewing brings you back.

## Scene 6 — Close (2:20–2:30)

**STAGE:** `/admin/members`, table in frame.

**VO:** Next: analytics, where these viewers turn into numbers.

## Rough edges

- The "Team" tab reads "Team member management coming soon." Do not open it.
- Grant/Revoke has no expiry field in the UI even though the feature spec
  mentions one. Do not promise an expiry date.
