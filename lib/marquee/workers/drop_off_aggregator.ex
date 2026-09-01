defmodule Marquee.Workers.DropOffAggregator do
  @moduledoc """
  Processes pending `PlaybackDropOff` events whose 1-hour return window has
  elapsed.

  For each pending row it:

    1. Discards the row if a newer drop-off exists on the same
       (viewer|user, video) pair (a later session supersedes).
    2. Discards the row if `Progress.updated_at > left_at` for the same
       subject/video (the viewer returned with fresh activity).
    3. Discards the row if `Progress.completed = true` (the video was
       finished — never counted as a drop-off per spec).
    4. Otherwise, increments the `VideoDropOffBucket` counter for the
       video/bucket and stamps `counted_at` + `outcome = "counted"`.

  Runs every 15 minutes via cron. Idempotent: `counted_at IS NOT NULL` rows
  are skipped on the next run.
  """

  use Oban.Worker, queue: :bulk, max_attempts: 3

  import Ecto.Query

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Marquee.Engagement.{PlaybackDropOff, Progress, VideoDropOffBucket}
  alias Marquee.Repo

  @return_window_minutes 60

  @impl true
  def perform(%Oban.Job{args: args, attempt: attempt}) do
    Marquee.Otel.extract_trace_context(args["trace_context"])
    Logger.metadata(worker: "DropOffAggregator")
    # Cross-org batch aggregator — no single organization_id applies.
    Tracer.set_attributes([
      {"oban.attempt", attempt},
      {"marquee.worker.platform_level", true}
    ])

    Tracer.with_span "marquee.worker.drop_off_aggregator" do
      cutoff = DateTime.add(DateTime.utc_now(), -@return_window_minutes * 60, :second)

      pending =
        PlaybackDropOff
        |> where([d], is_nil(d.counted_at) and d.left_at <= ^cutoff)
        |> order_by([d], asc: d.left_at)
        |> limit(1000)
        |> Repo.all()

      stats = Enum.reduce(pending, %{counted: 0, discarded: 0}, &process_row/2)

      Tracer.set_attributes([
        {"drop_off.pending_count", length(pending)},
        {"drop_off.counted", stats.counted},
        {"drop_off.discarded", stats.discarded}
      ])

      Logger.info("DropOffAggregator processed rows",
        pending_count: length(pending),
        counted: stats.counted,
        discarded: stats.discarded
      )

      :ok
    end
  end

  defp process_row(%PlaybackDropOff{} = row, acc) do
    case classify(row) do
      :count ->
        count_bucket(row)
        Map.update!(acc, :counted, &(&1 + 1))

      :discard ->
        discard(row)
        Map.update!(acc, :discarded, &(&1 + 1))
    end
  end

  defp classify(%PlaybackDropOff{} = row) do
    cond do
      superseded_by_later_drop_off?(row) -> :discard
      returned_via_progress?(row) -> :discard
      completed?(row) -> :discard
      true -> :count
    end
  end

  defp superseded_by_later_drop_off?(%PlaybackDropOff{} = row) do
    PlaybackDropOff
    |> where([d], d.id != ^row.id and d.video_id == ^row.video_id)
    |> where([d], d.left_at > ^row.left_at)
    |> scope_to_subject(row)
    |> Repo.exists?()
  end

  defp returned_via_progress?(%PlaybackDropOff{} = row) do
    Progress
    |> where([p], p.video_id == ^row.video_id)
    |> where([p], p.updated_at > ^row.left_at)
    |> scope_to_subject(row)
    |> Repo.exists?()
  end

  defp completed?(%PlaybackDropOff{} = row) do
    Progress
    |> where([p], p.video_id == ^row.video_id and p.completed == true)
    |> scope_to_subject(row)
    |> Repo.exists?()
  end

  defp scope_to_subject(query, %PlaybackDropOff{viewer_id: viewer_id})
       when not is_nil(viewer_id) do
    where(query, [x], x.viewer_id == ^viewer_id)
  end

  defp scope_to_subject(query, %PlaybackDropOff{user_id: user_id}) when not is_nil(user_id) do
    where(query, [x], x.user_id == ^user_id)
  end

  defp count_bucket(%PlaybackDropOff{} = row) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      bucket = upsert_bucket_counter(row, now)

      row
      |> Ecto.Changeset.change(counted_at: now, outcome: "counted")
      |> Repo.update!()

      bucket
    end)
  end

  defp discard(%PlaybackDropOff{} = row) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    row
    |> Ecto.Changeset.change(counted_at: now, outcome: "discarded")
    |> Repo.update!()
  end

  defp upsert_bucket_counter(%PlaybackDropOff{} = row, now) do
    %VideoDropOffBucket{}
    |> VideoDropOffBucket.changeset(%{
      organization_id: row.organization_id,
      video_id: row.video_id,
      bucket: row.bucket,
      count: 1
    })
    |> Repo.insert(
      on_conflict: [inc: [count: 1], set: [updated_at: now]],
      conflict_target: [:video_id, :bucket]
    )
  end
end
