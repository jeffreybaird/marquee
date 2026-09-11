defmodule Marquee.OtlpLogHandlerTest do
  use ExUnit.Case, async: true

  doctest Marquee.OtlpLogHandler

  @pb :opentelemetry_exporter_logs_service_pb
  @resource %{"service.name" => "marquee", "service.version" => "0.1.0"}

  # A span_ctx as the OTel SDK hands it to the handler: a tuple tagged
  # :span_ctx whose 2nd element is the 128-bit trace id and 4th the 64-bit
  # span id. These are the bytes the hub stores.
  @trace_int 0x0102030405060708090A0B0C0D0E0F10
  @span_int 0x1112131415161718
  @span_ctx {:span_ctx, @trace_int, :undefined, @span_int, :undefined, 1, true, false, :undefined}

  defp decode(body), do: @pb.decode_msg(body, :export_logs_service_request)

  defp only_record(events) do
    %{resource_logs: [%{scope_logs: [%{log_records: [record]}]}]} =
      decode(Marquee.OtlpLogHandler.encode_logs(events, @resource))

    record
  end

  describe "encode_logs/2 round-trips through the logs service decoder" do
    test "maps a string log event's fields" do
      event = %{
        level: :info,
        msg: {:string, "video created"},
        meta: %{time: 1_700_000_000_000_000, org_id: "org_123"},
        span_ctx: :undefined
      }

      record = only_record([event])

      # severity_number is a proto enum, so gpb decodes it to the spec atom
      # (the hub maps it back to the integer 9 on its side).
      assert record.severity_number == :SEVERITY_NUMBER_INFO
      assert record.severity_text == "info"
      assert record.body == %{value: {:string_value, "video created"}}
      # meta.time is microseconds; the record is nanoseconds.
      assert record.time_unix_nano == 1_700_000_000_000_000 * 1_000
      assert %{key: "org_id", value: %{value: {:string_value, "org_123"}}} in record.attributes
      # :time is internal logger metadata and must not leak as an attribute.
      refute Enum.any?(record.attributes, &(&1.key == "time"))
    end

    test "a structured report becomes a kvlist body" do
      event = %{
        level: :warning,
        msg: {:report, %{reason: "rate_limited"}},
        meta: %{},
        span_ctx: :undefined
      }

      record = only_record([event])

      assert record.severity_number == :SEVERITY_NUMBER_WARN
      assert {:kvlist_value, %{values: values}} = record.body.value
      assert %{key: "reason", value: %{value: {:string_value, "rate_limited"}}} in values
    end

    test "a record logged outside a span carries no trace or span id" do
      event = %{level: :info, msg: {:string, "no span"}, meta: %{}, span_ctx: :undefined}
      record = only_record([event])

      assert record.trace_id == ""
      assert record.span_id == ""
    end

    test "a record logged inside a span carries the span's trace and span ids" do
      event = %{level: :info, msg: {:string, "in span"}, meta: %{}, span_ctx: @span_ctx}
      record = only_record([event])

      assert record.trace_id == <<@trace_int::128>>
      assert record.span_id == <<@span_int::64>>
      assert byte_size(record.trace_id) == 16
      assert byte_size(record.span_id) == 8
    end

    test "the resource carries the trace resource attributes" do
      %{resource_logs: [%{resource: %{attributes: attrs}}]} =
        decode(Marquee.OtlpLogHandler.encode_logs([], @resource))

      assert %{key: "service.name", value: %{value: {:string_value, "marquee"}}} in attrs
      assert %{key: "service.version", value: %{value: {:string_value, "0.1.0"}}} in attrs
    end
  end
end
