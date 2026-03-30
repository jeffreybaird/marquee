defmodule Bobine.LogShipper do
  @moduledoc """
  Ships Elixir logger output to Grafana Cloud Loki via HTTP push.

  Attaches as a :logger handler in production when GRAFANA_LOKI_URL
  and GRAFANA_LOKI_AUTH are configured. Batches log entries and flushes
  every 5 seconds or when the batch reaches 100 entries.
  """

  use GenServer

  require Logger

  @batch_size 100
  @flush_interval_ms 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  def attach_logger_handler do
    :logger.add_handler(:loki_shipper, __MODULE__, %{})
  end

  # :logger handler callback — receives every log event
  def log(%{level: level, msg: msg, meta: meta}, _config) do
    if Process.whereis(__MODULE__) do
      message = format_message(msg)
      timestamp = Map.get(meta, :time, :os.system_time(:nanosecond))

      entry = %{
        level: level,
        message: message,
        timestamp: timestamp,
        meta: extract_meta(meta)
      }

      GenServer.cast(__MODULE__, {:log, entry})
    end

    :ok
  end

  # Required callback
  def adding_handler(config), do: {:ok, config}
  def removing_handler(_config), do: :ok
  def changing_config(_action, _old, new), do: {:ok, new}

  ## GenServer

  @impl true
  def init(opts) do
    url = Keyword.fetch!(opts, :url)
    auth = Keyword.fetch!(opts, :auth)

    schedule_flush()

    {:ok,
     %{
       url: url <> "/loki/api/v1/push",
       auth: auth,
       batch: []
     }}
  end

  @impl true
  def handle_cast({:log, entry}, state) do
    batch = [entry | state.batch]

    if length(batch) >= @batch_size do
      flush_batch(%{state | batch: batch})
      {:noreply, %{state | batch: []}}
    else
      {:noreply, %{state | batch: batch}}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    if state.batch != [] do
      flush_batch(state)
    end

    schedule_flush()
    {:noreply, %{state | batch: []}}
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval_ms)
  end

  defp flush_batch(%{url: url, auth: auth, batch: batch}) do
    values =
      batch
      |> Enum.reverse()
      |> Enum.map(fn entry ->
        ts = to_string(entry.timestamp)

        line =
          Jason.encode!(%{
            level: entry.level,
            msg: entry.message,
            org_id: entry.meta[:org_id],
            user_id: entry.meta[:user_id],
            request_id: entry.meta[:request_id],
            trace_id: entry.meta[:trace_id],
            span_id: entry.meta[:span_id]
          })

        [ts, line]
      end)

    payload =
      Jason.encode!(%{
        streams: [
          %{
            stream: %{app: "bobine", env: "production"},
            values: values
          }
        ]
      })

    headers = [
      {"content-type", "application/json"},
      {"authorization", "Basic #{auth}"}
    ]

    Task.start(fn ->
      case Req.post(url, body: payload, headers: headers, receive_timeout: 5_000) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Loki push failed: #{status} #{inspect(body)}")

        {:error, reason} ->
          Logger.warning("Loki push error: #{inspect(reason)}")
      end
    end)
  end

  defp format_message({:string, msg}), do: IO.iodata_to_binary(msg)
  defp format_message({:report, report}), do: inspect(report)
  defp format_message({format, args}), do: :io_lib.format(format, args) |> IO.iodata_to_binary()

  defp extract_meta(meta) do
    Map.take(meta, [:request_id, :trace_id, :span_id, :org_id, :user_id])
  end
end
