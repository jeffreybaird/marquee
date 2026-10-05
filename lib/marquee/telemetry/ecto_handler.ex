defmodule Marquee.Telemetry.EctoHandler do
  @moduledoc """
  Custom telemetry handler that wraps `OpentelemetryEcto` to prevent
  `source: "nil"` from appearing on spans for sourceless queries
  (transactions, raw SQL, Oban internals).

  When a query has no associated schema table, Ecto's telemetry metadata
  sets `source: nil`. The `opentelemetry_ecto` library writes this as the
  literal string `"nil"`, polluting dashboards grouped by source.

  This handler intercepts the metadata before delegation, replacing nil
  sources with a descriptive value based on the query type.
  """

  @doc """
  Attaches the Ecto OpenTelemetry handler with nil-source filtering.

  Call this instead of `OpentelemetryEcto.setup/2` in `application.ex`.
  Accepts the same options as `OpentelemetryEcto.setup/2`.
  """
  def setup(event_prefix, config \\ []) do
    event = event_prefix ++ [:query]
    :telemetry.attach({__MODULE__, event}, event, &handle_event/4, config)
  end

  @doc false
  def handle_event(event, measurements, %{source: nil} = metadata, config) do
    source = classify_sourceless_query(metadata)
    OpentelemetryEcto.handle_event(event, measurements, %{metadata | source: source}, config)
  end

  def handle_event(event, measurements, metadata, config) do
    OpentelemetryEcto.handle_event(event, measurements, metadata, config)
  end

  defp classify_sourceless_query(%{query: "BEGIN"}), do: "transaction"
  defp classify_sourceless_query(%{query: "COMMIT"}), do: "transaction"
  defp classify_sourceless_query(%{query: "ROLLBACK"}), do: "transaction"
  defp classify_sourceless_query(%{query: "SAVEPOINT " <> _}), do: "transaction"
  defp classify_sourceless_query(%{query: "RELEASE SAVEPOINT " <> _}), do: "transaction"
  defp classify_sourceless_query(_metadata), do: "raw_sql"
end
