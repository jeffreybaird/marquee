defmodule Marquee.Otel.ExporterConfig do
  @moduledoc """
  Resolves `:opentelemetry_exporter` settings for the personal OTLP hub from
  the runtime environment. Called by `config/runtime.exs` in prod, and reused
  to configure otlp_shipper's log/metrics export (`Marquee.Otel.Export`).

  Both the endpoint and the hub token are **required in prod**: a missing one
  raises so a release fails to boot loudly instead of silently dropping every
  span and log. In dev and test the exporter is left as `:none`, so these
  functions are never called there.

  The token comes from registering "marquee" at the hub's `/sources/new`; it
  is shown once and lives only in the runtime environment, never in config.
  """

  @endpoint_var "OTEL_EXPORTER_OTLP_ENDPOINT"
  @token_var "OTEL_HUB_TOKEN"

  @doc """
  Builds the `:opentelemetry_exporter` keyword settings from an environment map.

  Raises when `#{@endpoint_var}` or `#{@token_var}` is missing or blank.

      iex> settings = Marquee.Otel.ExporterConfig.settings(%{
      ...>   "OTEL_EXPORTER_OTLP_ENDPOINT" => "https://hub",
      ...>   "OTEL_HUB_TOKEN" => "s3cr3t"
      ...> })
      iex> {settings[:otlp_protocol], settings[:otlp_endpoint], settings[:otlp_headers]}
      {:http_protobuf, "https://hub", [{"authorization", "Bearer s3cr3t"}]}
  """
  def settings(env \\ System.get_env()) do
    [
      otlp_protocol: :http_protobuf,
      otlp_endpoint: endpoint(env),
      otlp_headers: [{"authorization", "Bearer " <> token(env)}]
    ]
  end

  @doc """
  Returns the hub endpoint from `#{@endpoint_var}`, raising if it is missing.

      iex> Marquee.Otel.ExporterConfig.endpoint(%{"OTEL_EXPORTER_OTLP_ENDPOINT" => "https://hub"})
      "https://hub"
  """
  def endpoint(env \\ System.get_env()), do: fetch_required!(env, @endpoint_var)

  @doc """
  Returns the per-source bearer token from `#{@token_var}`, raising if missing.

      iex> Marquee.Otel.ExporterConfig.token(%{"OTEL_HUB_TOKEN" => "s3cr3t"})
      "s3cr3t"
  """
  def token(env \\ System.get_env()), do: fetch_required!(env, @token_var)

  defp fetch_required!(env, key) do
    case Map.get(env, key) do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        raise """
        environment variable #{key} is missing.

        Both #{@endpoint_var} and #{@token_var} are required in production so
        Marquee can export OpenTelemetry traces and logs to the hub. Register
        "marquee" at the hub's /sources/new to obtain the token.
        """
    end
  end
end
