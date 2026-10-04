defmodule Marquee.Otel.ExportTest do
  use ExUnit.Case, async: true

  alias Marquee.Otel.Export
  alias Marquee.Otel.Metrics

  @config [endpoint: "https://hub.example", token: "s3cr3t"]

  test "returns no children when export is unconfigured" do
    assert Export.child_specs(nil, "1.0.0") == []
  end

  test "builds a log handler and metrics reporter sharing hub config" do
    assert [{OtlpShipper.LogHandler, log_opts}, {OtlpShipper.MetricsReporter, metric_opts}] =
             Export.child_specs(@config, "1.2.3")

    for opts <- [log_opts, metric_opts] do
      assert opts[:service_name] == "marquee"
      assert opts[:service_version] == "1.2.3"
      assert opts[:base_endpoint] == "https://hub.example"
      assert opts[:compression] == :gzip
      assert {"authorization", "Bearer s3cr3t"} in opts[:headers]
    end

    assert log_opts[:level] == :info
    assert metric_opts[:metrics] == Metrics.definitions()
  end
end
