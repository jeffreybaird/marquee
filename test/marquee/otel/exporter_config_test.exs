defmodule Marquee.Otel.ExporterConfigTest do
  use ExUnit.Case, async: true

  alias Marquee.Otel.ExporterConfig

  doctest ExporterConfig

  @env %{
    "OTEL_EXPORTER_OTLP_ENDPOINT" => "https://elixir-as-inf.diviningdad.com",
    "OTEL_HUB_TOKEN" => "tok_abc123"
  }

  describe "settings/1 with both variables present" do
    test "builds http/protobuf exporter settings with a bearer header" do
      settings = ExporterConfig.settings(@env)

      assert settings[:otlp_protocol] == :http_protobuf
      assert settings[:otlp_endpoint] == "https://elixir-as-inf.diviningdad.com"
      assert settings[:otlp_headers] == [{"authorization", "Bearer tok_abc123"}]
    end
  end

  # The prod runtime config (config/runtime.exs) calls these functions, so a
  # missing OTEL_EXPORTER_OTLP_ENDPOINT or OTEL_HUB_TOKEN must raise at boot
  # rather than silently disabling telemetry.
  describe "fail loudly when a required variable is missing" do
    test "raises when the endpoint is missing" do
      assert_raise RuntimeError, ~r/OTEL_EXPORTER_OTLP_ENDPOINT is missing/, fn ->
        ExporterConfig.settings(Map.delete(@env, "OTEL_EXPORTER_OTLP_ENDPOINT"))
      end
    end

    test "raises when the token is missing" do
      assert_raise RuntimeError, ~r/OTEL_HUB_TOKEN is missing/, fn ->
        ExporterConfig.settings(Map.delete(@env, "OTEL_HUB_TOKEN"))
      end
    end

    test "raises when a required variable is present but blank" do
      assert_raise RuntimeError, ~r/OTEL_HUB_TOKEN is missing/, fn ->
        ExporterConfig.settings(%{@env | "OTEL_HUB_TOKEN" => ""})
      end
    end

    test "endpoint/1 and token/1 raise independently on an empty environment" do
      assert_raise RuntimeError, ~r/OTEL_EXPORTER_OTLP_ENDPOINT/, fn ->
        ExporterConfig.endpoint(%{})
      end

      assert_raise RuntimeError, ~r/OTEL_HUB_TOKEN/, fn ->
        ExporterConfig.token(%{})
      end
    end
  end
end
