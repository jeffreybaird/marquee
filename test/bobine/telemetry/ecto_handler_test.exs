defmodule Bobine.Telemetry.EctoHandlerTest do
  use ExUnit.Case, async: false

  alias Bobine.Telemetry.EctoHandler

  @event [:test, :repo, :query]

  setup do
    # Set up an OTel span exporter that sends spans to this test process
    :otel_simple_processor.set_exporter(:otel_exporter_pid, self())

    on_exit(fn ->
      :telemetry.detach({EctoHandler, @event})
    end)

    :ok
  end

  defp base_measurements do
    %{
      total_time: System.convert_time_unit(1, :millisecond, :native),
      decode_time: nil,
      query_time: System.convert_time_unit(1, :millisecond, :native),
      queue_time: nil,
      idle_time: nil
    }
  end

  defp base_metadata(overrides) do
    Map.merge(
      %{
        query: "SELECT 1",
        source: nil,
        result: {:ok, %{num_rows: 0, rows: []}},
        repo: Bobine.Repo,
        type: :ecto_sql_query
      },
      overrides
    )
  end

  defp receive_span do
    assert_receive {:span, span}, 1000
    span
  end

  describe "nil source queries" do
    test "BEGIN gets source 'transaction'" do
      EctoHandler.handle_event(
        @event,
        base_measurements(),
        base_metadata(%{source: nil, query: "BEGIN"}),
        []
      )

      span = receive_span()
      assert span_attribute(span, :source) == "transaction"
    end

    test "COMMIT gets source 'transaction'" do
      EctoHandler.handle_event(
        @event,
        base_measurements(),
        base_metadata(%{source: nil, query: "COMMIT"}),
        []
      )

      span = receive_span()
      assert span_attribute(span, :source) == "transaction"
    end

    test "ROLLBACK gets source 'transaction'" do
      EctoHandler.handle_event(
        @event,
        base_measurements(),
        base_metadata(%{source: nil, query: "ROLLBACK"}),
        []
      )

      span = receive_span()
      assert span_attribute(span, :source) == "transaction"
    end

    test "SAVEPOINT gets source 'transaction'" do
      EctoHandler.handle_event(
        @event,
        base_measurements(),
        base_metadata(%{source: nil, query: "SAVEPOINT ecto_savepoint_1"}),
        []
      )

      span = receive_span()
      assert span_attribute(span, :source) == "transaction"
    end

    test "RELEASE SAVEPOINT gets source 'transaction'" do
      EctoHandler.handle_event(
        @event,
        base_measurements(),
        base_metadata(%{source: nil, query: "RELEASE SAVEPOINT ecto_savepoint_1"}),
        []
      )

      span = receive_span()
      assert span_attribute(span, :source) == "transaction"
    end

    test "unknown sourceless query gets source 'raw_sql'" do
      EctoHandler.handle_event(
        @event,
        base_measurements(),
        base_metadata(%{source: nil, query: "SELECT 1"}),
        []
      )

      span = receive_span()
      assert span_attribute(span, :source) == "raw_sql"
    end
  end

  describe "real source queries" do
    test "preserves the table name as source" do
      EctoHandler.handle_event(
        @event,
        base_measurements(),
        base_metadata(%{source: "videos", query: "SELECT * FROM videos"}),
        []
      )

      span = receive_span()
      assert span_attribute(span, :source) == "videos"
    end
  end

  describe "setup/2" do
    test "attaches a telemetry handler for the given prefix" do
      EctoHandler.setup([:test, :repo])

      handlers = :telemetry.list_handlers(@event)
      handler_ids = Enum.map(handlers, & &1.id)

      assert {EctoHandler, @event} in handler_ids
    end
  end

  # Extracts an attribute value from an OTel span record.
  # The span record tuple structure from :otel_simple_processor exports:
  # {:span, trace_id, span_id, traceflags, tracestate, parent_span_id,
  #  name, kind, start_time, end_time, attributes, events, links, status,
  #  instrumentation_scope}
  defp span_attribute(span, key) do
    attributes = elem(span, 10)

    case :otel_attributes.map(attributes) do
      map when is_map(map) -> Map.get(map, key)
    end
  end
end
