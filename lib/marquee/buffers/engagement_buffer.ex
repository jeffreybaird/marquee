defmodule Marquee.Buffers.EngagementBuffer do
  @moduledoc """
  In-memory write buffer for viewer engagement that would otherwise hit
  Postgres on every clip in the Shorts feed: completions and playback
  drop-offs.

  Entries:

    * `{:completion, %{organization_id:, viewer_id:, video_id:}}`:
      deduplicated per `{organization_id, viewer_id, video_id}` within a
      flush window; a flush applies `Marquee.Engagement.mark_completed/3`.
    * `{:drop_off, attrs}`: the attrs `Marquee.Engagement.record_drop_off/1`
      accepts (atom or string keys). A flush validates them with the same
      normalisation and batch-inserts the valid rows per organization,
      falling back to row-by-row inserts when a batch fails so valid rows
      still land. Invalid rows are logged and dropped.

  The buffer flushes every `:flush_interval_ms` (default: the
  `:engagement_buffer_flush_ms` app env, `:infinity` disables the timer),
  synchronously on `flush/0`, and when it terminates. A failing entry or
  organization never crashes the buffer or blocks other entries.
  """

  # A generous shutdown so the flush in terminate/2 can finish during deploys
  # instead of being killed after the default 5s.
  use GenServer, shutdown: 30_000

  @behaviour Marquee.Buffer

  require Logger
  require Marquee.Otel

  alias Marquee.Engagement

  @default_flush_interval_ms 5_000

  @doc """
  Starts a buffer. Options: `:name` (default this module) and
  `:flush_interval_ms`.

  Exempt from doctest — starts a process.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Queues an entry on the application buffer. Always returns `:ok`.

  Exempt from doctest — sends to a process.
  """
  @impl Marquee.Buffer
  def push(entry), do: push(__MODULE__, entry)

  @doc """
  Queues an entry on the given buffer. Always returns `:ok`.

  Exempt from doctest — sends to a process.
  """
  def push(server, entry) do
    GenServer.cast(server, {:push, stamp_entry(entry)})
  end

  @doc """
  Writes every pending entry of the application buffer before returning.

  Exempt from doctest — writes to the database.
  """
  @impl Marquee.Buffer
  def flush, do: flush(__MODULE__)

  @doc """
  Writes every pending entry of the given buffer before returning.

  Exempt from doctest — writes to the database.
  """
  def flush(server), do: GenServer.call(server, :flush, :infinity)

  # A drop-off happens when it is pushed, not when it is flushed.
  defp stamp_entry({:drop_off, attrs}) when is_map(attrs) do
    if Map.has_key?(attrs, :left_at) or Map.has_key?(attrs, "left_at"),
      do: {:drop_off, attrs},
      else:
        {:drop_off, Map.put(attrs, :left_at, DateTime.utc_now() |> DateTime.truncate(:second))}
  end

  defp stamp_entry(entry), do: entry

  ## Server

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    interval =
      Keyword.get_lazy(opts, :flush_interval_ms, fn ->
        Application.get_env(:marquee, :engagement_buffer_flush_ms, @default_flush_interval_ms)
      end)

    state = %{interval: interval, completions: %{}, drop_offs: []}
    schedule_flush(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:push, {:completion, %{} = entry}}, state) do
    case completion_key(entry) do
      {:ok, key} -> {:noreply, %{state | completions: Map.put_new(state.completions, key, key)}}
      :error -> {:noreply, log_invalid_entry(state, :completion, entry)}
    end
  end

  def handle_cast({:push, {:drop_off, %{} = attrs}}, state) do
    {:noreply, %{state | drop_offs: [attrs | state.drop_offs]}}
  end

  def handle_cast({:push, entry}, state) do
    {:noreply, log_invalid_entry(state, :unknown, entry)}
  end

  @impl GenServer
  def handle_call(:flush, _from, state) do
    {:reply, :ok, flush_pending(state)}
  end

  @impl GenServer
  def handle_info(:flush_tick, state) do
    state = flush_pending(state)
    schedule_flush(state)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    flush_pending(state)
    :ok
  end

  defp schedule_flush(%{interval: interval}) when is_integer(interval) and interval > 0,
    do: Process.send_after(self(), :flush_tick, interval)

  defp schedule_flush(_state), do: :ok

  defp completion_key(%{organization_id: org_id, viewer_id: viewer_id, video_id: video_id})
       when is_binary(org_id) and is_binary(viewer_id) and is_binary(video_id),
       do: {:ok, {org_id, viewer_id, video_id}}

  defp completion_key(_entry), do: :error

  defp log_invalid_entry(state, kind, entry) do
    Logger.warning("Engagement buffer dropped an invalid entry",
      kind: kind,
      org_id: org_id_of(entry)
    )

    state
  end

  ## Flushing

  defp flush_pending(%{completions: completions, drop_offs: drop_offs} = state)
       when map_size(completions) == 0 and drop_offs == [],
       do: state

  defp flush_pending(state) do
    Marquee.Otel.with_span "marquee.buffers.engagement_buffer.flush",
                           %{
                             "marquee.buffer.completions" => map_size(state.completions),
                             "marquee.buffer.drop_offs" => length(state.drop_offs)
                           } do
      state.completions |> Map.keys() |> Enum.each(&flush_completion/1)
      state.drop_offs |> Enum.reverse() |> flush_drop_offs()
    end

    %{state | completions: %{}, drop_offs: []}
  end

  defp flush_completion({org_id, viewer_id, video_id}) do
    guarded(org_id, "completion", fn ->
      case Engagement.complete_buffered(org_id, viewer_id, video_id) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Engagement buffer skipped a completion",
            org_id: org_id,
            video_id: video_id,
            reason: inspect(reason)
          )
      end
    end)
  end

  defp flush_drop_offs([]), do: :ok

  defp flush_drop_offs(entries) do
    entries
    |> Enum.map(&Engagement.buffered_drop_off_changeset/1)
    |> Enum.split_with(& &1.valid?)
    |> tap(fn {_valid, invalid} -> Enum.each(invalid, &log_invalid_drop_off/1) end)
    |> elem(0)
    |> Enum.group_by(&Ecto.Changeset.get_field(&1, :organization_id))
    |> Enum.each(fn {org_id, changesets} -> flush_org_drop_offs(org_id, changesets) end)
  end

  defp log_invalid_drop_off(changeset) do
    Logger.warning("Engagement buffer dropped an invalid drop-off",
      org_id: Ecto.Changeset.get_field(changeset, :organization_id),
      errors: inspect(Keyword.keys(changeset.errors))
    )
  end

  # One batch per organization; a failing batch falls back to row-by-row so
  # one bad row (e.g. a dangling video id) cannot take valid rows with it.
  defp flush_org_drop_offs(org_id, changesets) do
    case guarded(org_id, "drop-off batch", fn -> Engagement.insert_drop_off_batch(changesets) end) do
      {:ok, _count} -> :ok
      _failed -> insert_drop_offs_one_by_one(org_id, changesets)
    end
  end

  defp insert_drop_offs_one_by_one(org_id, changesets) do
    Enum.each(changesets, &guarded(org_id, "drop-off", fn -> Engagement.insert_drop_off(&1) end))
  end

  # Database and ownership errors must never crash the buffer.
  defp guarded(org_id, what, fun) do
    fun.()
  rescue
    error ->
      Logger.warning("Engagement buffer write failed",
        org_id: org_id,
        operation: what,
        error: Exception.message(error)
      )

      {:error, :write_failed}
  catch
    :exit, reason ->
      Logger.warning("Engagement buffer write exited",
        org_id: org_id,
        operation: what,
        reason: inspect(reason)
      )

      {:error, :write_failed}
  end

  defp org_id_of({_kind, %{} = attrs}),
    do: Map.get(attrs, :organization_id) || Map.get(attrs, "organization_id")

  defp org_id_of(%{} = attrs),
    do: Map.get(attrs, :organization_id) || Map.get(attrs, "organization_id")

  defp org_id_of(_entry), do: nil
end
