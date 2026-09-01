# Scaling Report

## Current bottlenecks found

1. The watch page is a full LiveView, so every passive viewer keeps a BEAM process and socket assigns alive for the whole session.
2. `WatchLive` was doing repeated database work on both the initial HTTP render and the websocket mount.
3. Viewer progress updates were writing directly to `progresses` on every periodic playback tick.
4. The Mux player hook sent synchronized 10-second progress updates, which would create bursty websocket traffic at scale.
5. Watch-page related content used the paginator, which added an unnecessary count query to a hot-path read.
6. The watch page hydrated the full queue on mount even when the viewer never opened or used it.
7. Queue/favorite/watchlist state used multiple independent lookups on mount instead of a compact watch-session bootstrap query.
8. Global PubSub events were duplicated whenever `Events.broadcast/2` was called with `scope=nil`.
9. Theme resolution still hit the database on every LiveView mount.
10. Fly was configured to scale to zero, which is risky for websocket-heavy traffic because reconnect storms and cold starts compound each other.

## Changes made

- Refactored `MarqueeWeb.Viewer.WatchLive` to use a lighter bootstrap:
  - watch video lookup is still explicit and scoped
  - related videos now use a dedicated cached watch query instead of paginated listing
  - queue state now starts as count-only and hydrates lazily when the queue panel is opened
  - watch state for favorited/watchlist/queue count/resume position uses a compact watch-session lookup
- Moved viewer playback progress off the hot write path:
  - `Marquee.Buffers.ProgressBuffer` now supports viewer-scoped buffering
  - `Engagement.update_progress/5` buffers viewer progress instead of writing directly to Postgres
  - `Engagement.get_progress/3` reads buffered viewer progress first so reconnects still resume accurately
  - `Engagement.mark_completed/3` now removes any stale buffered entry before writing completion state
- Reduced websocket event volume from the browser:
  - the Mux player hook now reports progress every 30 seconds instead of every 10
  - progress reporting is jittered to avoid synchronized bursts
  - final progress is flushed on page hide / visibility changes
- Added observability and guardrails:
  - watch mount telemetry with duration, query count, DB time, phase, and status
  - watch event volume telemetry
  - PubSub broadcast volume telemetry
  - LiveView mount/handle-event metrics tagged by view
  - fixed duplicate global broadcasts in `Marquee.Events`
- Added cached theme resolution for LiveView mount paths.
- Hardened Fly defaults for websocket traffic:
  - disabled scale-to-zero
  - kept one machine warm as a safer baseline
  - annotated concurrency settings as load-test placeholders
- Added/updated tests for:
  - viewer progress buffering and flushing
  - watch queue lazy hydration
  - new metrics events
  - corrected global PubSub broadcast behavior

## Why this matters for 100k viewers

- Passive viewers are cheaper because the watch page no longer eagerly hydrates queue state and no longer writes progress every few seconds.
- Reconnects are less expensive because related content and theme data are cached and the watch bootstrap is tighter.
- Websocket traffic is flatter because client progress messages are less frequent and intentionally de-synchronized.
- Postgres is better protected because the hottest viewer write path now batches in ETS and flushes later.
- PubSub fanout is lower because duplicate global broadcasts were removed.

## Recommended next load-test plan

1. Run a disconnected HTTP-only watch-page test to measure initial render latency and cache-hit behavior.
2. Run a websocket-heavy watch test with at least two cohorts:
   - mostly passive viewers who never open the queue
   - lightly interactive viewers who pause/resume and occasionally open the queue
3. Measure:
   - LiveView mount rate and latency
   - websocket message rate per node
   - `marquee.watch.mount.*` and `marquee.watch.event.*`
   - `marquee.pubsub.broadcast.*`
   - Repo query latency and queue time on watch requests
   - progress buffer flush batch size and flush latency
   - per-node memory growth and reductions from LiveView hibernation
4. Validate Fly concurrency and warm-machine settings under reconnect storm conditions, not just steady-state load.

## Remaining constraints before 100k viewers

- The watch page is still a full-page LiveView. The next major step is a static watch shell with smaller LiveView islands or controller/API-backed interactions for passive viewers.
- Viewer auth and organization resolution still do database work during LiveView connect. Those lookups should move behind short-lived cache layers with explicit invalidation.
- Queue/favorite/watchlist actions still hit Postgres synchronously on interaction. That is fine for lightweight interactivity, but not for high-frequency social overlays.
- Audit/global event broadcasting still exists for viewer-side engagement actions. If those events are not operationally required, they should be reduced further.
- No load-test-validated capacity numbers are claimed here; Fly concurrency, machine sizing, and hibernation settings are starting points only.
  