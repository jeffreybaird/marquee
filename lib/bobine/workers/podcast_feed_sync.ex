defmodule Bobine.Workers.PodcastFeedSync do
  @moduledoc """
  Polls remote podcast feeds and upserts episodes into the database.

  Two entry points:

    * The 15-minute cron tick (no args) sweeps every published
      `feed_import` show whose `remote_last_synced_at` is older than the
      sync window, and enqueues a per-show job for each.
    * A per-show job (`%{"show_id" => id}`) fetches the show's feed,
      parses it, and upserts each item.

  Failures are recorded on the `Bobine.Podcasts.Show` row (`remote_*`
  columns) so the operator dashboard can surface them. Three consecutive
  failures pause sync until manual operator intervention.
  """

  use Oban.Worker, queue: :bulk, max_attempts: 3

  require Logger

  import Ecto.Query, warn: false

  alias Bobine.Podcasts
  alias Bobine.Podcasts.{RemoteFeedClient, RemoteFeedParser, Show}
  alias Bobine.Repo

  @sync_window_seconds 15 * 60
  @failure_pause_threshold 3

  @impl true
  def perform(%Oban.Job{args: %{"show_id" => show_id}}) do
    case Repo.get(Show, show_id) do
      nil -> :ok
      %Show{deleted_at: %DateTime{}} -> :ok
      %Show{} = show -> sync_show(show)
    end
  end

  def perform(%Oban.Job{args: args}) when args == %{} or is_map(args) do
    enqueue_due_shows()
  end

  @doc """
  Enqueues a per-show sync job. Used by the operator dashboard's
  "Sync now" action.
  """
  def enqueue_for_show(%Show{id: show_id}) do
    %{"show_id" => show_id, "manual" => true}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp enqueue_due_shows do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@sync_window_seconds, :second)
      |> DateTime.truncate(:second)

    from(s in Show,
      where:
        s.source_type == "feed_import" and is_nil(s.deleted_at) and s.published == true and
          s.remote_consecutive_failures < @failure_pause_threshold and
          (is_nil(s.remote_last_synced_at) or s.remote_last_synced_at < ^cutoff),
      select: s.id
    )
    |> Repo.all()
    |> Enum.each(fn id ->
      %{"show_id" => id} |> __MODULE__.new() |> Oban.insert()
    end)

    :ok
  end

  defp sync_show(%Show{remote_feed_url: nil} = show) do
    record_failure(show, "missing remote_feed_url")
  end

  defp sync_show(%Show{remote_feed_url: url} = show) do
    Logger.metadata(org_id: show.organization_id, podcast_show_id: show.id)

    with {:ok, %{status: 200, body: body}} <- RemoteFeedClient.fetch(url),
         {:ok, parsed} <- RemoteFeedParser.parse(body) do
      Enum.each(parsed.episodes, &upsert_one(show, &1))
      record_success(show)
    else
      {:ok, %{status: status}} ->
        record_failure(show, "feed returned HTTP #{status}")

      {:error, :invalid_feed} ->
        record_failure(show, "feed body did not parse as RSS")

      {:error, reason} ->
        record_failure(show, "fetch failed: #{inspect(reason)}")
    end
  end

  defp upsert_one(show, item) do
    case Podcasts.upsert_episode_from_feed(show, item) do
      {:ok, _} -> :ok
      {:error, reason} -> log_upsert_failure(item, reason)
      {:error, _, _} = err -> log_upsert_failure(item, err)
    end
  end

  defp log_upsert_failure(item, reason) do
    Logger.warning("Episode upsert failed",
      guid: item[:guid],
      reason: inspect(reason)
    )
  end

  defp record_success(show) do
    show
    |> Show.remote_sync_changeset(%{
      remote_last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
      remote_last_sync_error: nil,
      remote_consecutive_failures: 0
    })
    |> Repo.update!()

    :ok
  end

  defp record_failure(show, message) do
    Logger.warning("Podcast feed sync failed",
      org_id: show.organization_id,
      podcast_show_id: show.id,
      reason: message
    )

    show
    |> Show.remote_sync_changeset(%{
      remote_last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
      remote_last_sync_error: message,
      remote_consecutive_failures: (show.remote_consecutive_failures || 0) + 1
    })
    |> Repo.update!()

    {:error, message}
  end
end
