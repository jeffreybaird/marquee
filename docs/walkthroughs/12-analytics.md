# 12 · Analytics

**Target length:** 3:00
**Audience:** owner or admin
**Pages:** `/admin/analytics`, per-video and per-series drill-ins
**Prerequisites:** an org with viewing data (demo org). Empty tables make this
script pointless.

## Scene 1 — Overview (0:00–0:35)

**STAGE:** `/admin/analytics`. Header "Analytics". Period selector buttons 7,
30, 90 (30 active). KPI cards: "Active Subscribers", "MRR", "Total Views",
"Avg Watch Time". Hover the tooltip on Active Subscribers ("Viewers with an
active or trialing subscription in the selected period."). Click 90; the
numbers change.

**VO:** Analytics opens on the last thirty days. Active subscribers, monthly
recurring revenue, total views and average watch time. Switch to seven or
ninety days at the top and every number and chart on the page follows.

## Scene 2 — Growth and revenue (0:35–1:00)

**STAGE:** Scroll to the subscriber growth chart and the daily revenue chart.
Hover a point on each.

**VO:** Below that, subscriber growth over time and daily revenue, straight
from Stripe. Hover any point for the exact figure.

## Scene 3 — Content performance (1:00–1:50)

**STAGE:** The content performance table: columns Title, "Unique Viewers",
"Avg Watch %", "Completion %", Watchlist, Favorites. Click the "Completion %"
header to sort. Page to page 2 and back. Click a video title.

**VO:** The content table is the part you'll come back to. Every video with
unique viewers, how far people get on average, how many finish, and how
often it's watchlisted or favorited. Sort by any column. Click a title to go
deeper.

## Scene 4 — Per-video drop-off (1:50–2:20)

**STAGE:** The per-video analytics page: drop-off distribution bar chart
across the video's length, plus bucket KPIs. Hover the tallest bar.

**VO:** For one video you get a drop-off chart: where in the runtime viewers
leave. A cliff at minute two usually means a slow open. A steady slope is
normal.

## Scene 5 — Series and seasons (2:20–2:45)

**STAGE:** Back on Analytics (or via a series row's "Analytics" link on
`/admin/series`): series analytics with per-season completion table and
overall KPIs. Click a season for the episode funnel chart, the drop-off
episode, and the next-season start rate.

**VO:** Series get their own view: completion per season, then per episode.
The funnel shows which episode loses people and how many go on to the next
season.

## Scene 6 — Engagement and churn, close (2:45–3:00)

**STAGE:** Scroll to the engagement block ("Continue Watching Rate", "Queue
Usage", "Avg Queue Size") and churn block ("Dunning", "Cancellations", "Trial
Conversion").

**VO:** Finally, engagement and churn: how many viewers resume, how many use
the queue, and how trials convert or fail. Next: the audit log.

## Rough edges

- On a fresh trial org every table is empty. Do not record there.
- Revenue charts read from Stripe events; a test-mode org needs a few
  completed test checkouts.
