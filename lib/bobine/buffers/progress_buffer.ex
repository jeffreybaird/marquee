defmodule Bobine.Buffers.ProgressBuffer do
  @moduledoc """
  ETS-backed buffer for playback progress updates. Coalesces rapid position
  updates and flushes to Postgres periodically, reducing write pressure.
  """

  use GenServer

  require Logger

  alias Bobine.Engagement.Progress
  alias Bobine.Repo

  @flush_interval_ms 30_000
  @table :progress_buffer
  @user :user
  @viewer :viewer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Writes a progress update to the buffer. Only the latest position per
  user+video pair is kept.
  """
  def update(org_id, user_id, video_id, position) do
    put_entry({@user, org_id, user_id, video_id}, %{position: position, duration: nil})
    :ok
  end

  @doc """
  Reads the buffered position for a user+video pair, or nil if none.
  """
  def get(org_id, user_id, video_id) do
    case get_entry({@user, org_id, user_id, video_id}) do
      %{position: position} -> position
      _ -> nil
    end
  end

  @doc """
  Writes a viewer progress update to the buffer.
  """
  def update_viewer(org_id, viewer_id, video_id, position, duration) do
    put_entry({@viewer, org_id, viewer_id, video_id}, %{position: position, duration: duration})
    :ok
  end

  @doc """
  Reads the buffered viewer progress entry, or nil if none.
  """
  def get_viewer(org_id, viewer_id, video_id) do
    case get_entry({@viewer, org_id, viewer_id, video_id}) do
      %{position: _position} = entry -> entry
      [] -> nil
      nil -> nil
    end
  end

  @doc """
  Deletes a buffered viewer progress entry.
  """
  def delete_viewer(org_id, viewer_id, video_id) do
    :ets.delete(@table, {@viewer, org_id, viewer_id, video_id})
    :ok
  end

  @doc """
  Clears all buffered entries. Useful in tests.
  """
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    ArgumentError -> :ok
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
      Logger.debug("Flushing progress entries", count: length(entries))

      Enum.each(entries, fn {key, entry, _ts} ->
        flush_entry_safely(key, entry)
        :ets.delete(@table, key)
      end)
    end
  end

  defp do_flush_entry({@user, org_id, user_id, video_id}, %{position: position}) do
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
      on_conflict: [set: [position: position, completed: false, updated_at: now]],
      conflict_target: [:user_id, :video_id, :organization_id]
    )
  end

  defp do_flush_entry(
         {@viewer, org_id, viewer_id, video_id},
         %{position: position, duration: duration}
       ) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(
      %Progress{
        organization_id: org_id,
        viewer_id: viewer_id,
        video_id: video_id,
        position: position,
        duration: duration,
        completed: false,
        inserted_at: now,
        updated_at: now
      },
      on_conflict: [
        set: [position: position, duration: duration, completed: false, updated_at: now]
      ],
      conflict_target:
        {:unsafe_fragment,
         ~s|("viewer_id","video_id","organization_id") WHERE viewer_id IS NOT NULL|}
    )
  end

  defp do_flush_entry({kind, org_id, subject_id, video_id}, _entry) do
    Logger.warning("Skipping unknown progress buffer entry",
      kind: inspect(kind),
      org_id: org_id,
      subject_id: subject_id,
      video_id: video_id
    )
  end

  defp do_flush_entry(_key, _entry), do: :ok

  defp get_entry(key) do
    case :ets.lookup(@table, key) do
      [{^key, entry, _ts}] -> entry
      [] -> nil
    end
  end

  defp put_entry(key, entry) do
    :ets.insert(@table, {key, entry, System.system_time(:second)})
  end

  defp flush_entry_safely(key, entry) do
    do_flush_entry(key, entry)
  rescue
    error ->
      Logger.error("Failed to flush progress buffer",
        org_id: org_id_from_key(key),
        key: inspect(key),
        entry: inspect(entry, pretty: true, limit: :infinity),
        error: inspect(error, pretty: true, limit: :infinity)
      )
  end

  defp org_id_from_key({_kind, org_id, _subject_id, _video_id}), do: org_id
  defp org_id_from_key(_), do: nil
end
