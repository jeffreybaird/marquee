---
name: observability
description: Use when adding or reviewing spans, metrics, telemetry events, trace context propagation, or logging context for business-significant operations in Marquee.
---

# Observability

Load this file when writing context functions, Oban workers, external API
client modules, or LiveViews. Traces and metrics are first-class citizens —
every operation that matters to the business must be observable.

---

## Export: the OTLP hub

All three signals go to the personal OTLP hub — there is no Grafana/Loki or
other backend.

| Signal | Shipped by | Hub path |
|---|---|---|
| Traces | `:opentelemetry_exporter` (configured in `config/runtime.exs`) | `/v1/traces` |
| Logs | `OtlpShipper.LogHandler`, started by `Marquee.Otel.Export` | `/v1/logs` |
| Metrics | `OtlpShipper.MetricsReporter`, started by `Marquee.Otel.Export` | `/v1/metrics` |

`Marquee.Otel.ExporterConfig` builds the settings from
`OTEL_EXPORTER_OTLP_ENDPOINT` (hub base URL) and `OTEL_HUB_TOKEN` (per-source
bearer token). Both are **required in prod** — the release raises at boot if
either is missing. Dev and test export nothing. See `.claude/deployment.md`
for how the values reach the droplet.

---

## Principles

1. **Every context mutation gets a span.** If a function creates, updates, or
   deletes something, wrap it in `Marquee.Telemetry.with_span/3`.

2. **Every external API call gets a span.** Mux, Stripe, and any future
   third-party call must produce a span with service-specific attributes.

3. **Every Oban worker gets a span with trace context.** Propagate the parent
   trace through job args so background processing connects to the triggering
   request.

4. **Every business-significant event gets a metric.** Video viewed, subscriber
   created, webhook delivered — if you'd put it on a dashboard, emit a
   telemetry event.

5. **Every log line carries context.** `trace_id`, `span_id`, `org_id`, and
   `user_id` must be in Logger metadata for every request and job.

---

## Span Naming Convention

```
marquee.<context>.<operation>
```

Examples:
- `marquee.content.create_video`
- `marquee.content.list_videos`
- `marquee.billing.create_checkout`
- `marquee.billing.cancel_subscription`
- `marquee.engagement.add_to_watchlist`
- `marquee.catalog.reorder_rows`
- `marquee.admin.create_organization`
- `marquee.admin.export_organization_data`
- `marquee.webhooks.dispatch`
- `marquee.imports.process_subscriber`

External services use the service name:
- `marquee.mux.create_upload_url`
- `marquee.mux.get_asset`
- `marquee.stripe.create_subscription`
- `marquee.stripe.create_checkout_session`

Oban workers:
- `marquee.worker.mux_webhook_processor`
- `marquee.worker.stripe_webhook_processor`
- `marquee.worker.webhook_delivery`
- `marquee.worker.analytics_aggregation`

---

## Standard Span Attributes

### Always include on org-scoped operations

```elixir
%{
  "marquee.org.id" => organization.id,
  "marquee.org.slug" => organization.slug
}
```

### On user-initiated operations

```elixir
%{
  "marquee.user.id" => user.id
}
```

**No PII in span attributes.** Never put email addresses, names, or other
personally identifiable information in span attributes. User ID is sufficient
for trace correlation. PII in the telemetry pipeline creates compliance risk.

### On external API calls

```elixir
%{
  "http.method" => "POST",
  "http.status_code" => 200,
  "marquee.idempotency_key" => key,
  "marquee.service" => "mux" | "stripe"
}
```

### On Oban workers

```elixir
%{
  "marquee.org.id" => org_id,
  "marquee.worker" => "MuxWebhookProcessor",
  "oban.queue" => "mux",
  "oban.attempt" => attempt
}
```

### On errors

Always set the span status and record the error:

```elixir
Tracer.set_status(:error, inspect(reason))
Tracer.set_attribute("error.type", error_atom_to_string(reason))
```

---

## How to Instrument a Context Function

### Mutation (create/update/delete)

```elixir
def create_video(scope, attrs) do
  Marquee.Telemetry.with_span "marquee.content.create_video",
    %{"marquee.org.id" => scope.organization.id} do
    with {:ok, video} <- do_create_video(scope, attrs) do
      Events.broadcast(scope, {:video_created, video})
      Metrics.video_upload_initiated(scope.organization.id)
      {:ok, video}
    end
  end
end
```

### Read (list/get)

```elixir
def list_videos(organization, opts \\ []) do
  Marquee.Telemetry.with_span "marquee.content.list_videos",
    %{"marquee.org.id" => organization.id, "page" => Keyword.get(opts, :page, 1)} do
    # ... query with pagination
  end
end
```

Read operations only need spans if they're complex (aggregations, multi-table
joins, filtered searches). A simple `Repo.get` does not need a custom span —
the Ecto auto-instrumentation covers it.

### External API call

```elixir
def create_upload_url(params) do
  key = Idempotency.key("create_upload", params.org_id, params.title)

  Tracer.with_span "marquee.mux.create_upload_url" do
    Tracer.set_attributes([
      {"marquee.service", "mux"},
      {"marquee.idempotency_key", key},
      {"marquee.org.id", params.org_id}
    ])

    case do_mux_request(params, key) do
      {:ok, result} ->
        Tracer.set_attribute("http.status_code", 200)
        Metrics.external_api_call("mux", "create_upload_url", duration_ms, :ok)
        {:ok, result}

      {:error, reason} ->
        Tracer.set_status(:error, inspect(reason))
        Metrics.external_api_call("mux", "create_upload_url", duration_ms, :error)
        {:error, :mux_error, reason}
    end
  end
end
```

---

## How to Instrument an Oban Worker

### Propagate trace context when enqueuing

```elixir
def enqueue(scope, worker_module, args) do
  trace_ctx = :otel_propagator_text_map.inject(:otel_ctx.get_current(), [])

  args
  |> Map.put(:trace_context, Map.new(trace_ctx))
  |> worker_module.new()
  |> Oban.insert()
end
```

### Restore context in the worker

```elixir
defmodule Marquee.Workers.MuxWebhookProcessor do
  use Oban.Worker, queue: :mux

  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def perform(%Oban.Job{args: args, attempt: attempt}) do
    # Restore parent trace context
    if ctx = args["trace_context"] do
      :otel_propagator_text_map.extract(ctx)
    end

    # Set Logger metadata for structured logs
    Logger.metadata(org_id: args["organization_id"])

    Tracer.with_span "marquee.worker.mux_webhook_processor",
      %{"marquee.org.id" => args["organization_id"], "oban.attempt" => attempt} do
      # ... process webhook
    end
  end
end
```

---

## How to Emit Metrics

### When to emit

Emit a metric when something happens that you'd want to count, track over
time, or alert on. Key signals:

| Event | Metric call |
|---|---|
| Video playback started | `Metrics.video_viewed(org_id, video_id)` |
| Upload initiated | `Metrics.video_upload_initiated(org_id)` |
| Subscriber created | `Metrics.subscription_created(org_id, plan)` |
| Subscriber canceled | `Metrics.subscription_canceled(org_id, plan)` |
| Webhook delivered | `Metrics.webhook_delivered(org_id, event_type, status)` |
| External API call | `Metrics.external_api_call(service, op, duration, status)` |
| Payment failed | `Metrics.payment_failed(org_id, reason)` |
| Migration subscriber imported | `Metrics.subscriber_imported(org_id)` |
| Migration subscriber converted | `Metrics.subscriber_converted(org_id)` |

### How to emit

Use `Marquee.Metrics` module. Every function emits a `:telemetry` event:

```elixir
Marquee.Metrics.video_viewed(org_id, video_id)
```

### Adding new metrics

When a new feature introduces a business-significant event:

1. Add a function to `Marquee.Metrics` that calls `:telemetry.execute/3`
2. Add the event to the handler list in `Marquee.TelemetryHandler.setup/0`
3. Add a test that verifies the telemetry event is emitted

---

## Structured Logging Rules

### Always use Logger with metadata, not string interpolation

```elixir
# ✅ CORRECT — structured, searchable, parseable
Logger.info("Video created",
  video_id: video.id,
  org_id: org.id,
  mux_asset_id: video.mux_asset_id
)

# ❌ WRONG — string interpolation, not searchable
Logger.info("Video #{video.id} created for org #{org.id}")
```

### Log levels

- `debug` — detailed trace information, query params, idempotency keys
- `info` — business events (video created, subscriber joined, webhook delivered)
- `warning` — recoverable issues (retry triggered, rate limit approaching, stale cache)
- `error` — failures requiring attention (Mux API error, Stripe payment failed, webhook delivery exhausted retries)

### What to log at each lifecycle point

**Context function entry (debug):**
```elixir
Logger.debug("Creating video", org_id: org.id, title: attrs[:title])
```

**Context function success (info):**
```elixir
Logger.info("Video created", video_id: video.id, org_id: org.id)
```

**Context function failure (warning or error):**
```elixir
Logger.warning("Video creation failed", org_id: org.id, reason: inspect(reason))
```

**External API call (info on success, error on failure):**
```elixir
Logger.info("Mux upload URL created", org_id: org.id, duration_ms: elapsed)
Logger.error("Mux API error", org_id: org.id, status: 503, body: truncated_body)
```

**Oban worker start (info):**
```elixir
Logger.info("Processing Mux webhook", org_id: org_id, event_type: type)
```

---

## Logger Metadata Setup

### In plugs (HTTP requests)

The `SetRequestContext` plug sets:
- `request_id` (from Phoenix)
- `org_id` (from resolved organization)
- `user_id` (from authenticated user)
- `org_slug` (for human-readable filtering)

`opentelemetry_logger_metadata` automatically adds:
- `trace_id`
- `span_id`

### In Oban workers

Set at the start of every `perform/1`:

```elixir
Logger.metadata(
  org_id: args["organization_id"],
  worker: __MODULE__ |> Module.split() |> List.last()
)
```

### In GenServers (event subscribers)

Set when handling a message:

```elixir
def handle_info({:marquee_event, {_action, _resource}, scope}, state) do
  Logger.metadata(
    org_id: scope.organization && scope.organization.id,
    user_id: scope.user && scope.user.id
  )
  # ... handle event
  {:noreply, state}
end
```

---

## Testing Observability Code

### What to test

- `Marquee.Metrics` functions emit the correct `:telemetry` events with
  the correct measurements and metadata. Use `:telemetry_test.attach_event_handlers/2`.
- `Marquee.Telemetry.with_span/3` passes through return values unchanged —
  both success and error tuples.
- Custom instrumentation does not change the behavior of the wrapped function.

### What NOT to test

- Span creation and attributes — that's OpenTelemetry's responsibility.
- Auto-instrumentation behavior — that's the library maintainers' job.
- Log output format — too brittle, changes with formatter config.

---

## LiveView Spans and HTTP Attributes

LiveView spans do **not** carry HTTP semantic convention attributes
(`http.route`, `http.method`, `http.status_code`, `http.target`,
`http.scheme`). This is by design — LiveView operates over an existing
WebSocket connection, so there is no HTTP request/response cycle per mount
or event.

HTTP-level observability comes from the **initial page load** span, which is
a regular HTTP request instrumented by `OpentelemetryPhoenix`. Once the page
loads and the LiveView WebSocket connects, subsequent mounts and events
produce LiveView-specific spans instead.

### SpanEnrichment on_mount hook

`MarqueeWeb.Hooks.SpanEnrichment` runs as the **last** `on_mount` hook in
every `live_session`. It enriches the current span with:

- `marquee.liveview.module` — the LiveView module name (e.g. `MarqueeWeb.Admin.ContentLive`)
- `marquee.liveview.connected` — `true` on connected mount, `false` on static render
- `marquee.org.id` — the current tenant's ID (if resolved)
- `marquee.org.slug` — the current tenant's slug (if resolved)
- `marquee.user.id` — the current operator user's ID (if authenticated)

This hook must always be listed **after** `AssignScope` (or equivalent)
in the `on_mount` list so that `current_scope` is populated.

### TelemetryOrgPlug for controller requests

`MarqueeWeb.Plugs.TelemetryOrgPlug` runs in the `:set_organization` pipeline
after `SetOrganization`. It sets `marquee.org.id`, `marquee.org.slug`, and
`marquee.user.id` on the current span for all non-LiveView HTTP requests
that resolve an organization.

---

## Mux Span Conventions

All Mux API calls produce spans named `marquee.mux.<operation>`. The
`MuxClient` module instruments every call with:

| Attribute | Description |
|---|---|
| `marquee.service` | Always `"mux"` |
| `marquee.mux.operation` | The operation name (e.g. `"create_direct_upload"`) |
| `marquee.org.id` | Tenant ID, read from Logger metadata |
| `http.status_code` | HTTP status on success |
| `duration_ms` | Client-side latency in milliseconds |

On error, the span status is set to `:error` with the reason.

### Example Mux span queries (TraceQL)

```
{resource.service.name="marquee" && span.marquee.service = "mux"}
{resource.service.name="marquee" && span.marquee.service = "mux" && duration > 500ms}
{resource.service.name="marquee" && span.marquee.mux.operation = "create_direct_upload"}
```

---

## Oban Worker Org Attribution

Every Oban worker that has `organization_id` in its args **must** call
`Tracer.set_attributes([{"marquee.org.id", org_id}])` at the start of
`perform/1`. This enables per-tenant filtering of background job traces.

```elixir
def perform(%Oban.Job{args: %{"organization_id" => org_id} = _args}) do
  Logger.metadata(org_id: org_id)
  Tracer.set_attributes([{"marquee.org.id", org_id}])
  # ... rest of worker logic
end
```

Workers that resolve org_id during processing (e.g. `StripeWebhookProcessor`
which reads it from event metadata) should set the attribute as soon as the
org_id is known.

---



When adding a new feature, verify:

- [ ] Context mutations wrapped in `Marquee.Telemetry.with_span/3`
- [ ] Span name follows `marquee.<context>.<operation>` convention
- [ ] Span attributes include `marquee.org.id` for org-scoped operations
- [ ] External API calls produce spans with service, status, and idempotency key
- [ ] Oban workers restore trace context and set Logger metadata
- [ ] Business-significant events emit metrics via `Marquee.Metrics`
- [ ] New metrics added to `TelemetryHandler.setup/0` event list
- [ ] Logger calls use structured metadata, not string interpolation
- [ ] Error paths set span status to `:error` with reason