defmodule Marquee.OtlpLogHandler do
  @moduledoc """
  A `:logger` handler that batches log events and posts them to the personal
  OTLP hub as OTLP/HTTP protobuf (`ExportLogsServiceRequest`), using the gpb
  modules shipped in `opentelemetry_exporter`.

  Copied (not depended on) from the hub's `examples/otlp_log_handler.ex`: the
  Erlang SDK's own `otel_log_handler` cannot export over OTLP today (the hex
  release calls an exporter module `opentelemetry_exporter` no longer ships,
  and main is mid-refactor), so this ~100-line handler is the source-side
  recipe. Revisit when a release of `opentelemetry_experimental` ships
  `otel_exporter_logs_otlp`; the hub side does not change either way.

  Added at boot in `Marquee.Application.start/2`, before the endpoint:

      :logger.add_handler(:otlp_logs, Marquee.OtlpLogHandler, %{
        level: :info,
        config: %{
          endpoint: endpoint,                                  # hub; /v1/logs is appended
          token: token,
          resource: %{"service.name" => "marquee", "service.version" => vsn},
          flush_ms: 5_000
        }
      })

  Trace and span ids come from the current span in the logging process, so
  records logged inside an `opentelemetry` span link to it and records outside
  one carry no ids. Structured reports (`Logger.info(%{...})`) become a
  `kvlist` body; everything else a string body. Logger metadata becomes
  attributes (internal keys dropped). The existing stdout `logger_json`
  handler is untouched — this runs alongside it.

  ## Known limits, decided not silently accepted

    * **No retry.** A failed POST drops that batch. This is telemetry: the
      handler must never block a caller or grow without bound, and the
      exporter-side contract for lost telemetry is "lost", not "replayed". We
      accept drop-on-failure rather than add a dependency or a replay queue.
    * **Bounded buffer.** To honour "never queue unboundedly", the in-memory
      batch is capped at `max_events` (default 10,000). Once full, new events
      are dropped until the next flush rather than risk OOM during a hub
      outage or a log burst. The drop count rides in state for introspection;
      it is not logged, to avoid a log→handler feedback loop.
  """
  use GenServer

  @pb :opentelemetry_exporter_logs_service_pb
  @default_max_events 10_000
  @internal_meta [
    :pid,
    :gl,
    :time,
    :mfa,
    :file,
    :line,
    :domain,
    :report_cb,
    :otel_trace_id,
    :otel_span_id,
    :otel_trace_flags,
    :crash_reason,
    :erl_level
  ]

  ## :logger handler callbacks

  @doc false
  def adding_handler(%{config: config} = handler_config) do
    # Not linked: logger runs this callback in a short-lived process.
    {:ok, pid} = GenServer.start(__MODULE__, config)
    {:ok, put_in(handler_config.config[:pid], pid)}
  end

  @doc false
  def removing_handler(%{config: %{pid: pid}}), do: GenServer.stop(pid)

  # Runs in the logging process, so the current span (if any) is readable here.
  @doc false
  def log(event, %{config: %{pid: pid}}) do
    GenServer.cast(pid, {:log, Map.put(event, :span_ctx, :otel_tracer.current_span_ctx())})
  end

  ## GenServer

  @impl true
  def init(config) do
    Process.flag(:trap_exit, true)
    flush_ms = Map.get(config, :flush_ms, 5_000)
    Process.send_after(self(), :flush, flush_ms)

    {:ok,
     %{
       config: config,
       flush_ms: flush_ms,
       max_events: Map.get(config, :max_events, @default_max_events),
       events: [],
       count: 0,
       dropped: 0
     }}
  end

  @impl true
  def handle_cast({:log, _event}, %{count: count, max_events: max} = state) when count >= max do
    {:noreply, %{state | dropped: state.dropped + 1}}
  end

  def handle_cast({:log, event}, state) do
    {:noreply, %{state | events: [event | state.events], count: state.count + 1}}
  end

  @impl true
  def handle_info(:flush, state) do
    Process.send_after(self(), :flush, state.flush_ms)
    {:noreply, flush(state)}
  end

  @impl true
  def terminate(_reason, state), do: flush(state)

  defp flush(%{events: []} = state), do: state

  defp flush(state) do
    state.events |> Enum.reverse() |> export(state.config)
    %{state | events: [], count: 0}
  end

  ## OTLP

  @doc """
  Encodes a batch of enriched log events into an `ExportLogsServiceRequest`
  protobuf binary, carrying the given resource attributes. Pure: builds the
  message with the gpb encoder and posts nothing.

      iex> body = Marquee.OtlpLogHandler.encode_logs([], %{"service.name" => "marquee"})
      iex> is_binary(body)
      true
  """
  def encode_logs(events, resource) do
    @pb.encode_msg(
      %{
        resource_logs: [
          %{
            resource: %{attributes: attributes(resource)},
            scope_logs: [
              %{
                scope: %{name: "Elixir.Logger", version: System.version()},
                log_records: Enum.map(events, &log_record/1)
              }
            ]
          }
        ]
      },
      :export_logs_service_request
    )
  end

  defp export(events, config) do
    body = encode_logs(events, Map.get(config, :resource, %{}))
    token = String.to_charlist(Map.get(config, :token, ""))
    headers = [{~c"authorization", ~c"Bearer " ++ token}]
    url = String.to_charlist(config.endpoint <> "/v1/logs")
    :httpc.request(:post, {url, headers, ~c"application/x-protobuf", body}, [], [])
  end

  defp log_record(%{level: level, msg: msg, meta: meta} = event) do
    {trace_id, span_id} = ids(Map.get(event, :span_ctx))

    %{
      time_unix_nano: Map.get(meta, :time, 0) * 1_000,
      observed_time_unix_nano: System.os_time(:nanosecond),
      severity_number: severity(level),
      severity_text: Atom.to_string(level),
      body: body(msg),
      attributes: meta |> Map.drop(@internal_meta) |> attributes(),
      trace_id: trace_id,
      span_id: span_id
    }
  end

  # A structured report becomes a kvlist body; everything else a string.
  defp body({:report, report}) when is_map(report) or is_list(report),
    do: %{value: {:kvlist_value, %{values: attributes(report)}}}

  defp body({:string, chardata}), do: %{value: {:string_value, IO.chardata_to_string(chardata)}}

  defp body({format, args}),
    do: %{value: {:string_value, format |> :io_lib.format(args) |> IO.chardata_to_string()}}

  # The SDK's span_ctx record: {:span_ctx, trace_id, trace_id_hex, span_id, span_id_hex, ...};
  # the integer ids are 0 when unset.
  defp ids(ctx) when is_tuple(ctx) and elem(ctx, 0) == :span_ctx and elem(ctx, 1) > 0 do
    {<<elem(ctx, 1)::128>>, <<elem(ctx, 3)::64>>}
  end

  defp ids(_), do: {<<>>, <<>>}

  defp attributes(map) do
    Enum.map(map, fn {k, v} -> %{key: to_string(k), value: any_value(v)} end)
  end

  defp any_value(v) when is_binary(v), do: %{value: {:string_value, v}}
  defp any_value(v) when is_boolean(v), do: %{value: {:bool_value, v}}
  defp any_value(v) when is_integer(v), do: %{value: {:int_value, v}}
  defp any_value(v) when is_float(v), do: %{value: {:double_value, v}}
  defp any_value(v) when is_atom(v), do: %{value: {:string_value, Atom.to_string(v)}}
  defp any_value(v), do: %{value: {:string_value, inspect(v)}}

  defp severity(:debug), do: 5
  defp severity(:info), do: 9
  defp severity(:notice), do: 10
  defp severity(:warning), do: 13
  defp severity(:error), do: 17
  defp severity(:critical), do: 18
  defp severity(:alert), do: 19
  defp severity(:emergency), do: 21
end
