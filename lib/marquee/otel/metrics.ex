defmodule Marquee.Otel.Metrics do
  @moduledoc """
  Curated `Telemetry.Metrics` definitions exported to the OTLP hub via
  `OtlpShipper.MetricsReporter`.

  This is deliberately **not** `MarqueeWeb.Telemetry.metrics/0`. That list feeds
  LiveDashboard and is mostly `summary/2`, which the OTLP reporter rejects at
  startup (`{:error, :unsupported_metric, :use_distribution}`). This list carries
  only the reporter's supported kinds — `counter`, `sum`, `last_value`,
  `distribution` — and is validated by `OtlpShipper.Metrics.Definition.new/1` in
  the tests.

  ## Cardinality

  Every selected tag becomes an OTLP series, and the reporter caps active series
  (default 1,000) then drops the rest. So these definitions tag only by
  low-cardinality dimensions (status, service, operation, plan, phase, event
  name). High-cardinality identifiers emitted in the same telemetry metadata —
  `org_id`, `video_id`, `plan_id`, PubSub `topic` — are intentionally **not**
  selected as metric tags; that context lives on traces and logs instead, where
  it does not multiply series.
  """

  import Telemetry.Metrics

  # External calls can be slow (Mux/Stripe); watch-page mounts should not be.
  @external_call_buckets_ms [10, 25, 50, 100, 250, 500, 1000, 2500, 5000]
  @watch_mount_buckets_ms [10, 25, 50, 100, 250, 500, 1000, 2500]

  @doc """
  Returns the OTLP-exportable metric definitions.

  Pure; safe to call without the reporter running. None are summaries.

      iex> defs = Marquee.Otel.Metrics.definitions()
      iex> Enum.any?(defs, &is_struct(&1, Telemetry.Metrics.Summary))
      false
  """
  def definitions do
    business_counters() ++ operational_counters() ++ distributions()
  end

  # Business events emitted by `Marquee.Metrics`. Tagged only where the emitted
  # metadata carries a low-cardinality dimension.
  defp business_counters do
    [
      counter("marquee.video.viewed.count"),
      counter("marquee.video.completed.count"),
      counter("marquee.video.upload_initiated.count"),
      counter("marquee.subscription.created.count", tags: [:plan]),
      counter("marquee.subscription.canceled.count", tags: [:plan]),
      counter("marquee.platform_subscription.created.count", tags: [:plan]),
      counter("marquee.platform_subscription.canceled.count"),
      counter("marquee.webhook.delivered.count", tags: [:event_type, :status]),
      counter("marquee.checkout.initiated.count"),
      counter("marquee.viewer_payment.failed.count"),
      counter("marquee.platform_payment.failed.count"),
      counter("marquee.playback.drop_off_recorded.count"),
      counter("marquee.queue.item_added.count"),
      counter("marquee.live_event.transitioned.count", tags: [:to_status]),
      counter("marquee.live_event.chat_message_sent.count"),
      counter("marquee.live_event.ppv_ticket_created.count")
    ]
  end

  # Watch-path and PubSub volume. `pubsub.broadcast` drops the `:topic` tag on
  # purpose — topics embed the org id and are unbounded.
  defp operational_counters do
    [
      counter("marquee.watch.mount.count", tags: [:phase, :status]),
      counter("marquee.watch.event.count", tags: [:event]),
      counter("marquee.pubsub.broadcast.count", tags: [:event])
    ]
  end

  # Durations are already in milliseconds when emitted, so the unit is a label,
  # not a `{:native, _}` conversion. Buckets are inclusive upper bounds in ms.
  defp distributions do
    [
      distribution("marquee.external_api.call.duration",
        unit: :millisecond,
        tags: [:service, :operation, :status],
        reporter_options: [buckets: @external_call_buckets_ms]
      ),
      distribution("marquee.watch.mount.duration",
        unit: :millisecond,
        tags: [:phase, :status],
        reporter_options: [buckets: @watch_mount_buckets_ms]
      )
    ]
  end
end
