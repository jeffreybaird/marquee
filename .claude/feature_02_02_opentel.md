# Task: Feature 2.2 — OpenTelemetry Instrumentation

Instrument the entire Bobine application with OpenTelemetry, treating traces
and metrics as first-class citizens. Every request, query, background job, and
external API call should produce telemetry data that can be shipped to any
OTel-compatible backend.

Follow all rules in CLAUDE.md. Load `.claude/architecture-decisions.md` and
`.claude/testing.md`.

This task has 6 parts. Do them in order. Run `mix test` after each part.

---

## Part 1: Dependencies and Core Configuration

### Add dependencies to `mix.exs`

```elixir
# OpenTelemetry core
{:opentelemetry, "~> 1.4"},
{:opentelemetry_api, "~> 1.3"},
{:opentelemetry_exporter, "~> 1.7"},

# Auto-instrumentation libraries
{:opentelemetry_phoenix, "~> 1.2"},
{:opentelemetry_ecto, "~> 1.2"},
{:opentelemetry_oban, "~> 1.1"},

# For outbound HTTP call instrumentation (Mux/Stripe API calls)
{:opentelemetry_finch, "~> 0.2"},

# Structured logging with trace context
{:opentelemetry_logger_metadata, "~> 0.1"},
```

Run `mix deps.get`.

### Configure OpenTelemetry in `config/config.exs`

```elixir
config :opentelemetry,
  resource: [
    service: [
      name: "bobine",
      version: Mix.Project.config()[:version]
    ]
  ],
  span_processor: :batch,
  traces_exporter: :otlp
```

### Configure exporter in `config/runtime.exs`

```elixir
if config_env() == :prod do
  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_endpoint: System.fetch_env!("OTEL_EXPORTER_OTLP_ENDPOINT")
end
```

### Configure for dev — export to console for visibility

```elixir
# config/dev.exs
config :opentelemetry,
  traces_exporter: {:otel_exporter_stdout, []}
```

### Configure for test — disable to avoid noise

```elixir
# config/test.exs
config :opentelemetry,
  traces_exporter: :none,
  span_processor: :simple
```

### Add OTEL_EXPORTER_OTLP_ENDPOINT to required env vars

Update `.claude/deployment.md` and the Fly secrets list. The endpoint depends
on which backend is chosen (Honeycomb, Grafana Cloud, Jaeger, etc.). For now,
make it configurable and document it.

---

## Part 2: Auto-Instrumentation Setup

### Install telemetry handlers in `application.ex`

Add to the `start/2` function in `lib/bobine/application.ex`, BEFORE the
supervision tree starts:

```elixir
def start(_type, _args) do
  # OpenTelemetry auto-instrumentation — must be called before supervision tree
  OpentelemetryPhoenix.setup(adapter: :bandit)
  OpentelemetryEcto.setup([:bobine, :repo])
  OpentelemetryOban.setup()

  children = [
    # ... existing children
  ]

  opts = [strategy: :one_for_one, name: Bobine.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### What this gives you for free

After this step, with zero changes to business logic, you get:

**Phoenix traces:**
- Span for every HTTP request with route, method, status code
- Span for every LiveView mount, handle_event, handle_info
- Request path, parameters, and response status as span attributes

**Ecto traces:**
- Span for every database query
- Query string, table name, and duration as span attributes
- Nested under the parent Phoenix/LiveView span

**Oban traces:**
- Span for every job execution
- Worker name, queue, attempt count as span attributes
- Job args available as span attributes

### Verify auto-instrumentation works

Start the dev server and perform some actions. With the stdout exporter
configured for dev, you should see trace output in the terminal. Verify:

- Loading a page produces a Phoenix span with nested Ecto spans
- Triggering a LiveView event produces spans
- If any Oban jobs run, they produce spans

---

## Part 3: Custom Spans for Domain Operations

Auto-instrumentation covers the infrastructure layer. Custom spans cover your
business logic — the things specific to Bobine that you need visibility into.

### Create `lib/bobine/telemetry.ex`

A helper module for creating spans with consistent naming and attributes:

```elixir
defmodule Bobine.Telemetry do
  @moduledoc """
  Helpers for creating OpenTelemetry spans in Bobine business logic.
  All span names follow the convention: bobine.<context>.<operation>
  """

  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Wraps a function in a named span with standard Bobine attributes.

  ## Example

      Bobine.Telemetry.with_span("bobine.content.create_video", %{org_id: org.id}) do
        do_create_video(scope, attrs)
      end
  """
  defmacro with_span(name, attributes \\ %{}, do: block) do
    quote do
      Tracer.with_span unquote(name), %{attributes: unquote(attributes)} do
        result = unquote(block)

        case result do
          {:ok, _} ->
            Tracer.set_attribute("outcome", "success")
            result

          {:error, reason} ->
            Tracer.set_attribute("outcome", "error")
            Tracer.set_attribute("error.reason", inspect(reason))
            result

          {:error, reason, _detail} ->
            Tracer.set_attribute("outcome", "error")
            Tracer.set_attribute("error.reason", inspect(reason))
            result

          other ->
            other
        end
      end
    end
  end

  @doc """
  Adds standard organization context attributes to the current span.
  Call this at the start of any org-scoped operation.
  """
  def set_org_attributes(%{id: org_id, slug: slug}) do
    Tracer.set_attributes([
      {"bobine.org.id", org_id},
      {"bobine.org.slug", slug}
    ])
  end

  def set_org_attributes(_), do: :ok

  @doc """
  Adds user context attributes to the current span.
  """
  def set_user_attributes(%{id: user_id, email: email}) do
    Tracer.set_attributes([
      {"bobine.user.id", user_id},
      {"bobine.user.email", email}
    ])
  end

  def set_user_attributes(_), do: :ok
end
```

### Instrument context functions

Add custom spans to key operations across all contexts. The pattern:

```elixir
defmodule Bobine.Content do
  require Bobine.Telemetry

  def create_video(scope, attrs) do
    Bobine.Telemetry.with_span "bobine.content.create_video",
      %{"bobine.org.id" => scope.organization.id} do
      with {:ok, video} <- do_create_video(scope, attrs) do
        Events.broadcast(scope, {:video_created, video})
        {:ok, video}
      end
    end
  end

  def list_videos(organization, opts \\ []) do
    Bobine.Telemetry.with_span "bobine.content.list_videos",
      %{"bobine.org.id" => organization.id, "page" => Keyword.get(opts, :page, 1)} do
      # ... existing implementation
    end
  end
end
```

### Which operations get custom spans

At minimum, wrap these in custom spans:

**Content context:**
- `create_video`, `update_video`, `delete_video`
- `create_upload_url` (includes Mux API call — important to trace)

**Billing context:**
- `create_checkout`, `cancel_subscription`
- Any function that calls Stripe

**Accounts context:**
- `create_organization`, `create_membership`

**Admin context:**
- `create_organization`, `export_organization_data`

**Webhooks context:**
- `dispatch` (outbound webhook delivery)

**Imports context (when built):**
- Each step of the migration pipeline

### Span naming convention

Follow OpenTelemetry semantic conventions:

```
bobine.<context>.<operation>

bobine.content.create_video
bobine.content.list_videos
bobine.billing.create_checkout
bobine.billing.cancel_subscription
bobine.admin.export_organization_data
bobine.webhooks.dispatch
bobine.mux.create_upload_url
bobine.stripe.create_subscription
```

---

## Part 4: External API Call Instrumentation

### Instrument MuxClient

Every Mux API call should produce a span nested under the parent operation.
The span should include: the Mux API endpoint, the HTTP method, the response
status, the latency, and the idempotency key.

```elixir
defmodule Bobine.Content.MuxClient do
  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def create_upload_url(params) do
    Tracer.with_span "bobine.mux.create_upload_url" do
      Tracer.set_attributes([
        {"mux.operation", "create_upload_url"},
        {"bobine.org.id", params[:organization_id]}
      ])

      case do_mux_request(params) do
        {:ok, result} ->
          Tracer.set_attribute("http.status_code", 200)
          {:ok, result}

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
          {:error, :mux_error, reason}
      end
    end
  end
end
```

### Instrument StripeClient

Same pattern as Mux. Every Stripe API call gets a span with:
- `stripe.operation` — the Stripe method being called
- `http.status_code` — the response status
- `stripe.idempotency_key` — the key used (for debugging retries)

```elixir
defmodule Bobine.Billing.StripeClient do
  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def create_subscription(customer_id, price_id) do
    key = Bobine.Idempotency.key("create_subscription", customer_id, price_id)

    Tracer.with_span "bobine.stripe.create_subscription" do
      Tracer.set_attributes([
        {"stripe.operation", "create_subscription"},
        {"stripe.idempotency_key", key}
      ])

      case do_stripe_request(customer_id, price_id, key) do
        {:ok, result} ->
          Tracer.set_attribute("http.status_code", 200)
          {:ok, result}

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
          {:error, :stripe_error, reason}
      end
    end
  end
end
```

### Instrument Oban workers with parent context

When a webhook arrives and enqueues an Oban job, the trace should connect the
HTTP request to the background job execution. Propagate the trace context
through the Oban job args:

```elixir
# When enqueuing — capture current trace context
def enqueue_mux_webhook(payload) do
  ctx = OpenTelemetry.Ctx.get_current()
  propagated = :otel_propagator_text_map.inject(ctx, [])

  %{payload: payload, trace_context: Map.new(propagated)}
  |> Bobine.Workers.MuxWebhookProcessor.new()
  |> Oban.insert()
end

# In the worker — restore trace context
defmodule Bobine.Workers.MuxWebhookProcessor do
  use Oban.Worker

  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def perform(%Oban.Job{args: %{"payload" => payload, "trace_context" => ctx}}) do
    # Restore parent trace context
    :otel_propagator_text_map.extract(ctx)

    Tracer.with_span "bobine.worker.mux_webhook_processor" do
      # ... process webhook
    end
  end
end
```

This means when you view a trace that starts with a Mux webhook HTTP request,
you can follow it through the Oban job execution and into whatever database
writes and side effects the worker triggers.

---

## Part 5: Metrics

### Create `lib/bobine/metrics.ex`

Define custom metrics for Bobine-specific business signals using
`:telemetry.execute/3`:

```elixir
defmodule Bobine.Metrics do
  @moduledoc """
  Custom metrics for Bobine business operations.
  Emits :telemetry events that can be consumed by any metrics backend.
  """

  @doc "Record a video view event"
  def video_viewed(org_id, video_id) do
    :telemetry.execute(
      [:bobine, :video, :viewed],
      %{count: 1},
      %{org_id: org_id, video_id: video_id}
    )
  end

  @doc "Record a subscription created event"
  def subscription_created(org_id, plan_name) do
    :telemetry.execute(
      [:bobine, :subscription, :created],
      %{count: 1},
      %{org_id: org_id, plan: plan_name}
    )
  end

  @doc "Record a subscription canceled event"
  def subscription_canceled(org_id, plan_name) do
    :telemetry.execute(
      [:bobine, :subscription, :canceled],
      %{count: 1},
      %{org_id: org_id, plan: plan_name}
    )
  end

  @doc "Record video upload initiated"
  def video_upload_initiated(org_id) do
    :telemetry.execute(
      [:bobine, :video, :upload_initiated],
      %{count: 1},
      %{org_id: org_id}
    )
  end

  @doc "Record external API call duration"
  def external_api_call(service, operation, duration_ms, status) do
    :telemetry.execute(
      [:bobine, :external_api, :call],
      %{duration: duration_ms},
      %{service: service, operation: operation, status: status}
    )
  end

  @doc "Record webhook delivery attempt"
  def webhook_delivered(org_id, event_type, status) do
    :telemetry.execute(
      [:bobine, :webhook, :delivered],
      %{count: 1},
      %{org_id: org_id, event_type: event_type, status: status}
    )
  end
end
```

### Create `lib/bobine/telemetry_handler.ex`

Attach handlers that convert `:telemetry` events into OpenTelemetry metrics:

```elixir
defmodule Bobine.TelemetryHandler do
  @moduledoc """
  Attaches :telemetry handlers for Bobine custom metrics and converts
  them to OpenTelemetry metric observations.
  """

  def setup do
    events = [
      [:bobine, :video, :viewed],
      [:bobine, :video, :upload_initiated],
      [:bobine, :subscription, :created],
      [:bobine, :subscription, :canceled],
      [:bobine, :external_api, :call],
      [:bobine, :webhook, :delivered],
      # Phoenix built-in events
      [:phoenix, :endpoint, :stop],
      [:phoenix, :live_view, :mount, :stop],
      [:phoenix, :live_view, :handle_event, :stop],
    ]

    :telemetry.attach_many(
      "bobine-metrics-handler",
      events,
      &handle_event/4,
      nil
    )
  end

  def handle_event([:bobine | _rest] = event, measurements, metadata, _config) do
    # Log structured metric data
    require Logger

    Logger.info("metric",
      event: Enum.join(event, "."),
      measurements: measurements,
      org_id: metadata[:org_id],
      metadata: Map.drop(metadata, [:org_id])
    )
  end

  def handle_event([:phoenix, :endpoint, :stop], measurements, metadata, _config) do
    # Track request latency
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info("metric",
      event: "phoenix.request",
      duration_ms: duration_ms,
      status: metadata.conn.status,
      route: metadata.conn.request_path
    )
  end

  def handle_event([:phoenix, :live_view | rest], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info("metric",
      event: "phoenix.live_view.#{Enum.join(rest, ".")}",
      duration_ms: duration_ms,
      view: inspect(metadata.socket.view)
    )
  end

  def handle_event(_, _, _, _), do: :ok
end
```

### Call setup in `application.ex`

Add `Bobine.TelemetryHandler.setup()` in the `start/2` function, alongside
the OpenTelemetry auto-instrumentation setup.

### Instrument context functions with metrics

Add metric calls alongside event broadcasts in context functions:

```elixir
def create_video(scope, attrs) do
  Bobine.Telemetry.with_span "bobine.content.create_video",
    %{"bobine.org.id" => scope.organization.id} do
    with {:ok, video} <- do_create_video(scope, attrs) do
      Events.broadcast(scope, {:video_created, video})
      Metrics.video_upload_initiated(scope.organization.id)
      {:ok, video}
    end
  end
end
```

---

## Part 6: Structured Logging with Trace Context

### Configure Logger for structured JSON output in prod

Add to `config/prod.exs` or `config/runtime.exs`:

```elixir
config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.Basic, []}

# Or if using a simpler approach:
config :logger, :default_formatter,
  format: {Bobine.LogFormatter, :format},
  metadata: [:request_id, :trace_id, :span_id, :org_id, :user_id]
```

Add dependency:

```elixir
{:logger_json, "~> 6.0"}  # if using LoggerJSON
```

### Inject trace context into Logger metadata

The `opentelemetry_logger_metadata` library automatically adds `trace_id` and
`span_id` to Logger metadata. Verify it's working by checking that log lines
in dev include these fields.

### Add org and user context to Logger metadata

In the `SetRequestContext` plug, also set Logger metadata:

```elixir
def call(conn, _opts) do
  scope = conn.assigns[:current_scope]

  Logger.metadata(
    org_id: get_in(scope, [:organization, :id]),
    user_id: get_in(scope, [:user, :id]),
    org_slug: get_in(scope, [:organization, :slug])
  )

  Bobine.RequestContext.put(%{
    # ... existing fields
  })

  conn
end
```

### Add org context to Oban worker logs

At the start of every Oban worker's `perform/1`, set Logger metadata:

```elixir
def perform(%Oban.Job{args: %{"organization_id" => org_id} = args}) do
  Logger.metadata(org_id: org_id)
  # ... rest of worker
end
```

### The goal

Every log line in production should include:
- `trace_id` — links to the distributed trace
- `span_id` — links to the specific span
- `org_id` — which tenant this log belongs to
- `user_id` — which user triggered this (if applicable)
- `request_id` — Phoenix request ID for correlation

This means you can:
1. See a log line like `"Mux webhook processing failed"`
2. Filter by `org_id` to see all logs for that tenant
3. Click the `trace_id` to see the full distributed trace
4. See the HTTP request that received the webhook, the Oban job that processed
   it, the Ecto queries it ran, and the error that occurred — all in one view

---

## Tests

### Do not test OpenTelemetry internals

Do not write tests that assert on span creation, metric values, or trace
propagation. These are infrastructure concerns, not business logic. The
auto-instrumentation libraries are well-tested by their maintainers.

### Do test that instrumentation doesn't break business logic

All existing tests must continue to pass. The instrumentation is additive —
wrapping a function in `with_span` must not change its return value or behavior.

### Test the Metrics module

```elixir
defmodule Bobine.MetricsTest do
  use ExUnit.Case, async: true

  test "video_viewed/2 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:bobine, :video, :viewed]])

    Bobine.Metrics.video_viewed("org_123", "video_456")

    assert_received {[:bobine, :video, :viewed], ^ref, %{count: 1},
                     %{org_id: "org_123", video_id: "video_456"}}
  end

  test "external_api_call/4 emits telemetry event with duration" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:bobine, :external_api, :call]])

    Bobine.Metrics.external_api_call("mux", "create_asset", 150, :ok)

    assert_received {[:bobine, :external_api, :call], ^ref, %{duration: 150},
                     %{service: "mux", operation: "create_asset", status: :ok}}
  end
end
```

### Test the Telemetry helper

```elixir
defmodule Bobine.TelemetryTest do
  use ExUnit.Case, async: true

  require Bobine.Telemetry

  test "with_span returns the wrapped function's result" do
    result = Bobine.Telemetry.with_span "test.span" do
      {:ok, "hello"}
    end

    assert result == {:ok, "hello"}
  end

  test "with_span passes through error tuples" do
    result = Bobine.Telemetry.with_span "test.span" do
      {:error, :not_found}
    end

    assert result == {:error, :not_found}
  end
end
```

---

## Definition of Done

- [ ] OpenTelemetry dependencies installed and configured
- [ ] Dev exports to stdout, test exports nothing, prod exports to OTLP endpoint
- [ ] Auto-instrumentation active for Phoenix, Ecto, and Oban
- [ ] `Bobine.Telemetry` helper module with `with_span` macro
- [ ] Custom spans on all key context operations with consistent naming
- [ ] MuxClient and StripeClient produce spans with service-specific attributes
- [ ] Trace context propagates from HTTP requests through Oban jobs
- [ ] `Bobine.Metrics` module emitting `:telemetry` events for business metrics
- [ ] `Bobine.TelemetryHandler` attaching handlers for custom and Phoenix events
- [ ] Logger configured with trace_id, span_id, org_id, user_id metadata
- [ ] Oban workers set Logger metadata with org_id at start of perform
- [ ] All existing tests pass unchanged
- [ ] Metrics module has telemetry event tests
- [ ] Telemetry helper has pass-through behavior tests
- [ ] `mix format`, `mix credo --strict`, and `mix dialyzer` all pass
- [ ] `OTEL_EXPORTER_OTLP_ENDPOINT` documented in deployment config
- [ ] 