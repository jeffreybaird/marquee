defmodule Marquee.Otel.MetricsTest do
  use ExUnit.Case, async: true

  alias Marquee.Otel.Metrics
  alias OtlpShipper.Metrics.Definition

  test "definitions compile cleanly under the OTLP reporter's own validation" do
    # OtlpShipper.Metrics.Definition.new/1 is exactly what MetricsReporter runs
    # at startup: it rejects summaries, duplicate OTLP names, unsupported units,
    # and histograms without buckets. If this passes, the reporter boots.
    assert {:ok, compiled} = Definition.new(Metrics.definitions())
    assert length(compiled) == length(Metrics.definitions())
  end

  test "contains no summary definitions (the reporter rejects them)" do
    refute Enum.any?(Metrics.definitions(), &is_struct(&1, Telemetry.Metrics.Summary))
  end

  test "every distribution declares strictly increasing histogram buckets" do
    for %Telemetry.Metrics.Distribution{} = dist <- Metrics.definitions() do
      buckets = dist.reporter_options[:buckets]
      assert is_list(buckets) and buckets != []
      assert buckets == Enum.sort(buckets)
      assert buckets == Enum.uniq(buckets)
    end
  end

  test "does not select high-cardinality identifiers as metric tags" do
    banned = [:org_id, :video_id, :plan_id, :user_id, :topic]

    for metric <- Metrics.definitions(), tag <- metric.tags do
      refute tag in banned,
             "#{inspect(metric.name)} selects high-cardinality tag #{inspect(tag)}"
    end
  end

  test "output names are unique" do
    names = Enum.map(Metrics.definitions(), & &1.name)
    assert names == Enum.uniq(names)
  end
end
