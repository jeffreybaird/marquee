defmodule Marquee.TelemetryHandler do
  @moduledoc """
  Attaches :telemetry handlers for Marquee custom metrics and converts
  them to structured log output for observability backends.
  """

  require Logger

  @doc """
  Attaches telemetry event handlers. Called during application startup.
  """
  def setup do
    events = [
      [:marquee, :tenant_domain, :transition],
      [:marquee, :video, :viewed],
      [:marquee, :video, :upload_initiated],
      [:marquee, :subscription, :created],
      [:marquee, :subscription, :canceled],
      [:marquee, :external_api, :call],
      [:marquee, :webhook, :delivered],
      [:marquee, :watch, :mount],
      [:marquee, :watch, :event],
      [:marquee, :pubsub, :broadcast],
      [:phoenix, :endpoint, :stop],
      [:phoenix, :live_view, :mount, :stop],
      [:phoenix, :live_view, :handle_event, :stop]
    ]

    :telemetry.attach_many(
      "marquee-metrics-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc false
  def handle_event([:marquee | _rest] = event, measurements, metadata, _config) do
    Logger.info("metric",
      event: Enum.join(event, "."),
      measurements: measurements,
      org_id: metadata[:org_id],
      metadata: Map.drop(metadata, [:org_id])
    )
  end

  def handle_event([:phoenix, :endpoint, :stop], measurements, metadata, _config) do
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
