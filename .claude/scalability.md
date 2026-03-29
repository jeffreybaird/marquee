# Scalability

Load this file when building any feature that handles viewer-facing traffic,
writes high-frequency data, or introduces new database queries. Every feature
should be built with the assumption that the platform will eventually support
1 million concurrent viewers across all tenants.

We don't need to handle that load today. We need to make decisions today that
don't prevent us from handling it later.

---

## Guiding Principle

Mux handles video delivery. Our infrastructure handles everything around the
video: authentication, session management, homepage rendering, playback
tracking, analytics, watchlists, and the operator dashboard. Design every
feature knowing that a million viewers will never touch Mux through us — but
they will hit our database, our LiveView connections, our caches, and our
background job queues.

---

## Database: Protect Postgres from the Hot Path

### Never write high-frequency data directly to Postgres

Any operation that fires more than once per viewer per minute must not
write directly to `Repo`. Use a write buffer that batches and flushes.

**High-frequency operations:**
- Playback progress updates (every 10–30 seconds per viewer)
- Analytics view events (every video play, pause, seek, complete)
- Heartbeat / "still watching" pings

**Pattern: Write Buffer**

```elixir
defmodule Bobine.Buffer do
  @moduledoc """
  Behaviour for write buffers that batch high-frequency operations
  and flush periodically.
  """

  @callback write(key :: term(), value :: term()) :: :ok
  @callback flush() :: :ok
end
```

The default implementation uses ETS with a GenServer that flushes to Postgres
on a timer (every 30 seconds) or when the buffer reaches a size threshold.
The interface allows swapping to Redis, Kafka, or a dedicated time-series
store later without changing any caller.

```elixir
# Context function stays clean — callers never know about the buffer
def update_progress(scope, video_id, position) do
  Bobine.Buffers.ProgressBuffer.write(
    {scope.user.id, video_id},
    %{position: position, updated_at: DateTime.utc_now()}
  )
end
```

### Never insert analytics events one at a time

Analytics events are append-only and high volume. Always batch them:

```elixir
# ❌ WRONG — one insert per event in the hot path
def record_view(scope, video_id) do
  Repo.insert(%AnalyticsEvent{...})
end

# ✅ CORRECT — buffer and batch flush
def record_view(scope, video_id) do
  Bobine.Buffers.AnalyticsBuffer.write(
    :video_view,
    %{org_id: scope.organization.id, user_id: scope.user.id,
      video_id: video_id, occurred_at: DateTime.utc_now()}
  )
end
```

### Separate read and write paths

Structure context functions so that reads can be routed to a replica and
writes go to the primary. Don't mix reads and writes in a single function
unless transactional consistency is actually required.

```elixir
# ✅ CORRECT — pure read, can run against a replica
def list_videos(organization, opts \\ []) do
  Video
  |> where(organization_id: ^organization.id)
  |> where([v], is_nil(v.deleted_at))
  |> order_by(desc: :inserted_at)
  |> Pagination.paginate(opts)
end

# ✅ CORRECT — pure write, must hit primary
def create_video(scope, attrs) do
  # ...
end

# ❌ AVOID — mixed read+write that forces primary for everything
def create_video_and_return_catalog(scope, attrs) do
  {:ok, video} = do_create_video(scope, attrs)
  videos = list_videos(scope.organization)  # this read is now on primary
  {:ok, video, videos}
end
```

You don't need to implement read replicas now. But when you do, it should
be a routing change in the Repo layer, not a rewrite of context functions.

### Index strategy

Every query that runs in the viewer hot path must be backed by an index. At
minimum, every tenant-scoped table needs:

- Index on `organization_id` (already required by multi-tenancy rules)
- Composite index on `[organization_id, <sort_column>]` for listing queries
- Composite index on `[organization_id, user_id]` for user-scoped lookups
  (watchlist, favorites, progress, subscriptions)

When adding a new query to a context function, check `EXPLAIN ANALYZE` in
dev to verify it's using an index. Log any sequential scan on a table with
more than 1000 rows.

---

## LiveView Connections: Minimize Persistent State

### Viewer-facing pages should minimize LiveView connections

A million concurrent viewers means a million WebSocket connections if every
page is a full LiveView. Each connection holds a BEAM process with socket
assigns in memory.

**Strategy: Islands Architecture**

Viewer-facing pages should render as static server-rendered HTML by default.
Interactive elements (watchlist button, progress bar, "continue watching" row)
mount as targeted LiveView components within the static page.

```heex
<%!-- Static page shell — no persistent WebSocket --%>
<main>
  <h1><%= @video.title %></h1>

  <%!-- LiveView island for the interactive player + progress --%>
  <%= live_render(@conn, BobineWeb.Viewer.PlayerComponent,
    session: %{"video_id" => @video.id, "org_id" => @organization.id}
  ) %>

  <%!-- Static content below --%>
  <p><%= @video.description %></p>
</main>
```

This dramatically reduces the number of persistent connections while
preserving interactivity where it matters.

**What should be full-page LiveView:**
- Operator dashboard (always — low concurrent users, high interactivity)
- Viewer account/settings page (low traffic)
- Watchlist management page (moderate traffic, high interactivity)

**What should be static with LiveView islands:**
- Homepage / browse pages (high traffic, mostly read-only)
- Video player page (high traffic, only player controls are interactive)
- Search results (high traffic, mostly read-only)

### Keep socket assigns lean

Every byte in `socket.assigns` is held in memory for the lifetime of the
connection. Never preload entire association trees into assigns. Load the
minimum needed for render, and fetch on demand for interactions.

```elixir
# ❌ WRONG — loads everything into memory
def mount(_params, _session, socket) do
  videos = Content.list_videos(socket.assigns.organization)
             |> Repo.preload([:tags, :collections, :analytics_events])
  {:ok, assign(socket, videos: videos)}
end

# ✅ CORRECT — minimal data, load details on demand
def mount(_params, _session, socket) do
  %{results: videos} = Content.list_videos(socket.assigns.organization,
    per_page: 25, fields: [:id, :title, :mux_playback_id, :slug])
  {:ok, assign(socket, videos: videos)}
end
```

---

## Caching: The Layer Between Viewers and Postgres

### All frequently-read, infrequently-written data goes through cache

If data is read on every page load but only changes when an operator makes
an edit, it must be cached.

**What to cache:**
- Organization resolution (slug → org) — TTL: 5 minutes
- Theme per org — until invalidated
- Row/layout configuration per org — until invalidated
- Video catalog metadata — TTL: 1 minute
- Subscription status per user+org — TTL: 1 minute
- Feature flags per org — TTL: 5 minutes

**What NOT to cache:**
- Playback progress (per-user, per-video, changes constantly)
- Analytics events (write-only)
- Audit logs (write-only)
- Real-time viewer counts (derived from connections, not DB)

### Cache implementation

Use a `Bobine.Cache` behaviour with a default ETS/Cachex implementation:

```elixir
defmodule Bobine.Cache do
  @callback fetch(key :: String.t(), opts :: keyword(), fallback :: fun()) ::
    term()
  @callback invalidate(key :: String.t()) :: :ok
  @callback invalidate_pattern(pattern :: String.t()) :: :ok
end
```

Context functions read through the cache transparently:

```elixir
def get_theme(organization) do
  Cache.fetch("theme:#{organization.id}", ttl: :timer.minutes(5), fn ->
    Repo.get_by(Theme, organization_id: organization.id)
  end)
end
```

### Cache invalidation via events

When an operator updates a cached resource, the event broadcast triggers
cache invalidation across the cluster:

```elixir
defmodule Bobine.Events.CacheSubscriber do
  def handle_event(_scope, {:theme_updated, theme}) do
    Cache.invalidate("theme:#{theme.organization_id}")
  end

  def handle_event(_scope, {:row_updated, row}) do
    Cache.invalidate("rows:#{row.organization_id}")
  end

  def handle_event(_scope, {:organization_updated, org}) do
    Cache.invalidate("org:slug:#{org.slug}")
    Cache.invalidate("org:domain:#{org.custom_domain}")
  end
end
```

Since Phoenix PubSub propagates across the Fly cluster, cache invalidation
on one node invalidates on all nodes.

---

## PubSub: Only Broadcast What Multiple Processes Need

### Rules for PubSub usage

**DO broadcast:**
- Content changes (video published, row reordered) — operators and viewers
  on the same org need to see updates
- Subscriber events (new subscriber, cancellation) — operator dashboard
  real-time counters
- Operator actions (video deleted, settings changed) — other operators in
  the same org see the change live
- Cache invalidation signals

**DO NOT broadcast:**
- Playback progress updates — single-session state, no other process cares
- Analytics events — write to buffer, not PubSub
- Per-viewer UI state — scroll position, expanded accordions, filter selections
- Heartbeats or "still watching" pings

### Topic design

All PubSub topics must be scoped to the narrowest useful audience:

```elixir
# ✅ Org-scoped — only processes interested in this org
"events:#{org_id}"

# ✅ Resource-scoped — only processes watching this specific resource
"video:#{video_id}"

# ✅ Admin-scoped — only operator dashboard processes for this org
"admin:#{org_id}"

# ❌ Global topic with high-frequency messages
"all_events"

# ❌ Per-viewer topic that nobody else subscribes to
"viewer:#{user_id}:progress"
```

### At scale

If PubSub over Erlang distribution becomes a bottleneck (every message goes
to every node), the migration path is:

1. Move high-volume topics to Redis PubSub (Phoenix.PubSub.Redis adapter)
2. Keep low-volume topics on native Erlang distribution
3. Or: route PubSub messages through a dedicated message broker (NATS, RabbitMQ)

This is a configuration change in the PubSub adapter, not a code change,
as long as you follow the topic design rules above.

---

## Background Jobs: Separate by Criticality

### Queue hierarchy

```elixir
config :bobine, Oban,
  queues: [
    critical: 10,    # Subscription changes, payment processing
    default: 20,     # Webhook delivery, notifications, email
    mux: 10,         # Mux webhook processing
    stripe: 10,      # Stripe webhook processing
    bulk: 5,          # Analytics aggregation, progress flushes, exports
    imports: 3        # Migration/import jobs
  ]
```

### Rules

- **Never put high-volume work in `critical` or `default` queues.** Analytics
  flushes, progress batch writes, and data exports go in `bulk`.
- **Payment-related jobs go in `critical`.** A queue backlog in analytics
  must never delay a subscription activation or payment confirmation.
- **Tag every job with `organization_id`** (already in architecture-decisions.md).
  This enables per-tenant monitoring and future fair-scheduling.
- **Set timeouts per queue.** Critical jobs should time out quickly and retry
  fast. Bulk jobs can run longer with slower retries.

### At scale

If Oban's Postgres-backed queue becomes a bottleneck (millions of jobs per
hour), the migration path is Oban Pro with SmartEngine (partitioned queues,
rate limiting per tenant) or moving high-volume queues to a dedicated job
processor (Redis-backed Sidekiq equivalent or a custom GenStage pipeline).

The Oban Worker interface stays the same. Only the queue configuration changes.

---

## Rate Limiting: Per-Tenant Protection

### Every external-facing route needs rate limiting

A misbehaving tenant, a bot, or an attack on one tenant must not affect
other tenants.

### Implementation

Build a rate limit plug now, even if the limits are generous:

```elixir
defmodule BobineWeb.Plugs.RateLimit do
  @moduledoc """
  Token bucket rate limiter. Configurable per route and per tenant.
  Default implementation uses ETS. Swappable to Redis at scale.
  """

  def init(opts), do: opts

  def call(conn, opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    limit = Keyword.get(opts, :limit, 100)
    period = Keyword.get(opts, :period, :timer.minutes(1))
    key = build_key(conn, Keyword.get(opts, :key, :ip))

    case check_rate(bucket, key, limit, period) do
      :ok -> conn
      :rate_limited ->
        conn
        |> put_resp_header("retry-after", to_string(div(period, 1000)))
        |> send_resp(429, "Rate limit exceeded")
        |> halt()
    end
  end

  defp build_key(conn, :ip), do: to_string(:inet.ntoa(conn.remote_ip))
  defp build_key(conn, :organization_id), do: conn.assigns[:organization][:id]
  defp build_key(conn, :user_id), do: conn.assigns[:current_scope][:user][:id]
end
```

### Suggested limits (generous starting point)

| Route scope | Key | Limit | Period |
|---|---|---|---|
| Viewer pages | `organization_id + ip` | 200 req | 1 minute |
| Viewer API | `organization_id + user_id` | 100 req | 1 minute |
| Webhook receivers | `ip` | 500 req | 1 minute |
| Admin pages | `organization_id + user_id` | 300 req | 1 minute |
| Super admin | `user_id` | 300 req | 1 minute |
| Auth endpoints | `ip` | 10 req | 1 minute |

### At scale

The ETS-based rate limiter works on a single node. In a multi-node Fly
cluster, each node has its own counters — effective limits are multiplied
by the number of nodes. For strict enforcement at scale, move to a shared
Redis counter with `INCR` + `EXPIRE`. The plug interface stays the same.

---

## Tenant Isolation Under Load

### One tenant must never degrade another tenant's experience

This is the most important scalability principle for multi-tenant SaaS.

**Database:** If one org has 100K videos, their listing queries shouldn't
slow down an org with 50 videos. Ensure all queries are indexed and
paginated. Consider per-org query timeouts.

**Background jobs:** If one org triggers a bulk import of 10K videos, their
Oban jobs shouldn't starve other orgs' webhook processing. Use queue
separation and consider per-org job concurrency limits.

**Cache:** One org's cache invalidation storm (updating all their rows at
once) shouldn't evict another org's cached data. Use org-namespaced cache
keys so eviction is scoped.

**Connections:** One org's viewers shouldn't consume all available LiveView
connections. This is harder to enforce at the BEAM level — the main lever
is keeping viewer pages lightweight (islands architecture) so each
connection uses minimal resources.

**Rate limiting:** Already covered above — per-tenant rate limits prevent
one org from monopolizing resources.

---

## Checklist for New Features

When building a new feature, verify:

- [ ] High-frequency writes use a buffer, not direct Repo inserts
- [ ] Viewer-facing pages minimize persistent LiveView connections
- [ ] Socket assigns contain only the minimum data needed for render
- [ ] Frequently-read data goes through the cache layer
- [ ] Cache keys are org-namespaced for scoped invalidation
- [ ] PubSub is only used for broadcast-worthy events, not per-viewer state
- [ ] PubSub topics are scoped to the narrowest useful audience
- [ ] Background jobs are in the correct queue by criticality
- [ ] Database queries in the viewer hot path are indexed
- [ ] Rate limiting is applied to any new external-facing route
- [ ] Read and write paths are separable for future read-replica support
- [ ] One tenant's usage cannot degrade another tenant's experience