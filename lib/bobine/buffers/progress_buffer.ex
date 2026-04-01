defmodule Bobine.Buffers.ProgressBuffer do
  @moduledoc """
  ETS-backed buffer for playback progress updates. Coalesces rapid position
  updates and flushes to Postgres periodically, reducing write pressure.
  """

  use GenServer

  require Logger

  alias Bobine.Repo
  alias Bobine.Engagement.Progress

  @flush_interval_ms 30_000
  @table :progress_buffer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Writes a progress update to the buffer. Only the latest position per
  user+video pair is kept.
  """
  def update(org_id, user_id, video_id, position) do
    :ets.insert(@table, {{org_id, user_id, video_id}, position, System.system_time(:second)})
    :ok
  end

  @doc """
  Reads the buffered position for a user+video pair, or nil if none.
  """
  def get(org_id, user_id, video_id) do
    case :ets.lookup(@table, {org_id, user_id, video_id}) do
      [{_key, position, _ts}] -> position
      [] -> nil
    end
  end

  @doc """
  Forces an immediate flush of all buffered data to Postgres.
  Useful in tests.
  """
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_flush()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:flush, state) do
    do_flush()
    schedule_flush()
    {:noreply, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    do_flush()
    {:reply, :ok, state}
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval_ms)
  end

  defp do_flush do
    entries = :ets.tab2list(@table)

    if entries != [] do
      Logger.debug("Flushing #{length(entries)} progress entries")

      Enum.each(entries, fn {{org_id, user_id, video_id}, position, _ts} ->
        upsert_progress(org_id, user_id, video_id, position)
        :ets.delete(@table, {org_id, user_id, video_id})
      end)
    end
  end

  defp upsert_progress(org_id, user_id, video_id, position) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(
      %Progress{
        organization_id: org_id,
        user_id: user_id,
        video_id: video_id,
        position: position,
        completed: false,
        inserted_at: now,
        updated_at: now
      },
      on_conflict: [set: [position: position, updated_at: now]],
      conflict_target: [:user_id, :video_id, :organization_id]
    )
  rescue
    error ->
      Logger.error(
        "Failed to flush progress org_id=#{org_id} " <>
          "user_id=#{user_id} " <>
          "video_id=#{video_id} " <>
          "error=#{inspect(error, pretty: true, limit: :infinity)}"
      )
  end
end
