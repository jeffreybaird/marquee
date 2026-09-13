defmodule Marquee.Otel.Export do
  @moduledoc """
  Builds the `otlp_shipper` child specs that ship Marquee's logs and metrics to
  the personal OTLP hub.

  Traces are exported separately by `:opentelemetry_exporter` (configured in
  `config/runtime.exs`); this module only covers the two signals the Erlang SDK
  cannot yet export over OTLP: logs (`OtlpShipper.LogHandler`) and metrics
  (`OtlpShipper.MetricsReporter`).

  Both children own their own Finch pool and buffer, authenticate to the hub
  with the per-source bearer token, and share the trace exporter's endpoint and
  `service.name`. Export is enabled only when `:otlp_export` is configured — set
  in prod `runtime.exs` when the hub endpoint and token are present, and absent
  in dev/test, where `child_specs/2` returns `[]`.
  """

  alias Marquee.Otel.Metrics

  @doc """
  Returns the log/metrics child specs, or `[]` when export is not configured.

  `config` is the `:otlp_export` keyword (`:endpoint`, `:token`) or `nil`;
  `vsn` is the release version recorded as `service.version`.

      iex> specs = Marquee.Otel.Export.child_specs([endpoint: "https://hub.example", token: "tok"], "1.2.3")
      iex> length(specs)
      2
      iex> Marquee.Otel.Export.child_specs(nil, "1.2.3")
      []
  """
  def child_specs(
        config \\ Application.get_env(:marquee, :otlp_export),
        vsn \\ marquee_version()
      )

  def child_specs(config, vsn) when is_list(config) do
    common = [
      service_name: "marquee",
      service_version: vsn,
      base_endpoint: Keyword.fetch!(config, :endpoint),
      headers: [{"authorization", "Bearer " <> Keyword.fetch!(config, :token)}],
      compression: :gzip
    ]

    [
      {OtlpShipper.LogHandler, [level: :info] ++ common},
      {OtlpShipper.MetricsReporter, [metrics: Metrics.definitions()] ++ common}
    ]
  end

  def child_specs(_config, _vsn), do: []

  defp marquee_version, do: :marquee |> Application.spec(:vsn) |> to_string()
end
