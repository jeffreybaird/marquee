defmodule Bobine.Analytics do
  @moduledoc """
  Analytics context — operator-facing metrics for an organization.

  All functions are scoped to an organization and wrapped in telemetry spans.
  Read-only except for `upsert_snapshot/1` (used by the background worker).
  Overview cards and engagement metrics are cached for 5 minutes.
  """

  import Ecto.Query

  require Bobine.Otel

  alias Bobine.Accounts.Organization
  alias Bobine.Analytics.Snapshot
  alias Bobine.Billing.{Plan, ViewerSubscription}
  alias Bobine.Cache
  alias Bobine.Content.{Episode, Season, Series, Video}

  alias Bobine.Engagement.{
    Favorite,
    PlaybackDropOff,
    Progress,
    QueueItem,
    VideoDropOffBucket,
    WatchlistItem
  }

  alias Bobine.Repo

  @cache_ttl :timer.minutes(5)

  # ---------------------------------------------------------------------------
  # Overview cards
  # ---------------------------------------------------------------------------

  @doc """
  Returns high-level KPI cards for the given period.

  Returns `%{active_subscribers, mrr_cents, total_views, avg_watch_time_seconds}`.
  Cached per org + period for 5 minutes.

  Exempt from doctest — hits the database.
  """
  def get_overview_cards(%Organization{} = org, period) do
    key = "analytics:overview:#{org.id}:#{period}"

    Cache.fetch(key, [ttl: @cache_ttl], fn ->
      Bobine.Otel.with_span "bobine.analytics.get_overview_cards",
                            %{"bobine.org.id" => org.id} do
        active_subscribers = count_active_subscribers(org.id)
        mrr_cents = compute_mrr_cents(org.id)
        total_views = count_views_in_period(org.id, period)
        avg_watch_time = compute_avg_watch_time(org.id, period)

        %{
          active_subscribers: active_subscribers,
          mrr_cents: mrr_cents,
          total_views: total_views,
          avg_watch_time_seconds: avg_watch_time
        }
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Subscriber time series
  # ---------------------------------------------------------------------------

  @doc """
  Returns daily subscriber counts for a date range from snapshots.

  Today's count is computed live.

  Exempt from doctest — hits the database.
  """
  def list_daily_subscriber_counts(%Organization{} = org, from_date, to_date) do
    Bobine.Otel.with_span "bobine.analytics.list_daily_subscriber_counts",
                          %{"bobine.org.id" => org.id} do
      historical =
        Snapshot
        |> where(
          [s],
          s.organization_id == ^org.id and
            s.metric_type == "daily_subscribers" and
            s.period_date >= ^from_date and
            s.period_date < ^to_date
        )
        |> order_by(asc: :period_date)
        |> Repo.all()

      today = Date.utc_today()

      if Date.compare(to_date, today) != :lt do
        live_count = count_active_subscribers(org.id)
        live_entry = %{period_date: today, value: Decimal.new(live_count)}
        historical_without_today = Enum.reject(historical, &(&1.period_date == today))
        historical_without_today ++ [live_entry]
      else
        historical
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Revenue time series
  # ---------------------------------------------------------------------------

  @doc """
  Returns daily revenue snapshots for a date range.

  Exempt from doctest — hits the database.
  """
  def list_daily_revenue(%Organization{} = org, from_date, to_date) do
    Bobine.Otel.with_span "bobine.analytics.list_daily_revenue",
                          %{"bobine.org.id" => org.id} do
      Snapshot
      |> where(
        [s],
        s.organization_id == ^org.id and
          s.metric_type == "daily_revenue" and
          s.period_date >= ^from_date and
          s.period_date <= ^to_date
      )
      |> order_by(asc: :period_date)
      |> Repo.all()
    end
  end

  # ---------------------------------------------------------------------------
  # Content performance
  # ---------------------------------------------------------------------------

  @doc """
  Returns paginated content performance stats for the given period.

  Columns: title, unique_viewers, avg_watch_percentage, completion_rate,
  watchlist_adds, favorites.

  Sortable via `sort_by` option (`:unique_viewers`, `:completion_rate`,
  `:avg_watch_percentage`, `:watchlist_adds`, `:favorites`).

  Returns `%{results, page, per_page, total, total_pages}`.

  Exempt from doctest — hits the database.
  """
  def list_content_performance(%Organization{} = org, period, opts \\ []) do
    Bobine.Otel.with_span "bobine.analytics.list_content_performance",
                          %{"bobine.org.id" => org.id} do
      page = Keyword.get(opts, :page, 1)
      per_page = min(Keyword.get(opts, :per_page, 20), 100)
      sort_by = Keyword.get(opts, :sort_by, :unique_viewers)
      sort_dir = Keyword.get(opts, :sort_dir, :desc)

      from_date = period_start_date(period)

      video_ids =
        Video
        |> where([v], v.organization_id == ^org.id and is_nil(v.deleted_at))
        |> select([v], v.id)
        |> Repo.all()

      if video_ids == [] do
        %{results: [], page: page, per_page: per_page, total: 0, total_pages: 0}
      else
        rows = build_content_rows(org.id, video_ids, from_date, sort_by, sort_dir)

        total = length(rows)
        total_pages = max(ceil(total / per_page), 1)
        offset = (page - 1) * per_page
        paginated = Enum.slice(rows, offset, per_page)

        %{
          results: paginated,
          page: page,
          per_page: per_page,
          total: total,
          total_pages: total_pages
        }
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Drop-off buckets (per video)
  # ---------------------------------------------------------------------------

  @doc """
  Returns the top drop-off bucket for each video ID.

  Used by the content performance table to show a single "worst bucket" per
  row. Returns a map of `video_id => %{bucket, count, start_seconds,
  end_seconds}`. Videos with no drop-off data are absent from the map.

  Exempt from doctest — hits the database.
  """
  def top_drop_off_buckets_by_video(%Organization{} = org, video_ids)
      when is_list(video_ids) do
    Bobine.Otel.with_span "bobine.analytics.top_drop_off_buckets_by_video",
                          %{"bobine.org.id" => org.id} do
      if video_ids == [] do
        %{}
      else
        VideoDropOffBucket
        |> where([b], b.organization_id == ^org.id and b.video_id in ^video_ids)
        |> Repo.all()
        |> Enum.group_by(& &1.video_id)
        |> Map.new(fn {video_id, rows} ->
          top = Enum.max_by(rows, & &1.count)

          {video_id,
           %{
             bucket: top.bucket,
             count: top.count,
             start_seconds: top.bucket * PlaybackDropOff.bucket_size(),
             end_seconds: (top.bucket + 1) * PlaybackDropOff.bucket_size()
           }}
        end)
      end
    end
  end

  @doc """
  Returns the drop-off distribution for a single video.

  Includes every bucket with confirmed drop-offs and its share of the total
  as a percentage. Used by the video analytics page to render the bar chart.
  Cached per video for 5 minutes.

  Returns `%{total: int, buckets: [%{bucket, count, start_seconds,
  end_seconds, percentage}]}` sorted by bucket index ascending.

  Exempt from doctest — hits the database.
  """
  def drop_off_distribution(%Organization{} = org, video_id) do
    key = "analytics:drop_off:#{video_id}"

    Cache.fetch(key, [ttl: @cache_ttl], fn ->
      Bobine.Otel.with_span "bobine.analytics.drop_off_distribution",
                            %{"bobine.org.id" => org.id, "bobine.video.id" => video_id} do
        fetch_distribution_from_db(org.id, video_id)
      end
    end)
  end

  defp fetch_distribution_from_db(org_id, video_id) do
    rows =
      VideoDropOffBucket
      |> where([b], b.organization_id == ^org_id and b.video_id == ^video_id)
      |> order_by([b], asc: b.bucket)
      |> Repo.all()

    total = rows |> Enum.map(& &1.count) |> Enum.sum()

    buckets =
      Enum.map(rows, fn row ->
        percentage =
          if total > 0, do: Float.round(row.count / total * 100, 1), else: 0.0

        %{
          bucket: row.bucket,
          count: row.count,
          start_seconds: row.bucket * PlaybackDropOff.bucket_size(),
          end_seconds: (row.bucket + 1) * PlaybackDropOff.bucket_size(),
          percentage: percentage
        }
      end)

    %{total: total, buckets: buckets}
  end

  # ---------------------------------------------------------------------------
  # Engagement metrics
  # ---------------------------------------------------------------------------

  @doc """
  Returns engagement metrics for the given period.

  Includes queue usage, continue-watching conversion rate, and top queued
  videos. Cached per org + period for 5 minutes.

  Exempt from doctest — hits the database.
  """
  def get_engagement_metrics(%Organization{} = org, period) do
    key = "analytics:engagement:#{org.id}:#{period}"

    Cache.fetch(key, [ttl: @cache_ttl], fn ->
      Bobine.Otel.with_span "bobine.analytics.get_engagement_metrics",
                            %{"bobine.org.id" => org.id} do
        from_date = period_start_date(period)

        total_viewers = count_viewers_with_progress(org.id, from_date)
        continue_watching = count_viewers_with_multiple_views(org.id, from_date)

        continue_watching_rate =
          if total_viewers > 0,
            do: Float.round(continue_watching / total_viewers * 100, 1),
            else: 0.0

        queue_viewer_count = count_viewers_with_queue(org.id)
        total_viewer_count = count_all_viewers(org.id)

        queue_usage_pct =
          if total_viewer_count > 0,
            do: Float.round(queue_viewer_count / total_viewer_count * 100, 1),
            else: 0.0

        avg_queue_size = compute_avg_queue_size(org.id)
        most_queued = most_queued_videos(org.id)

        %{
          continue_watching_conversion_rate: continue_watching_rate,
          queue_usage_percent: queue_usage_pct,
          avg_queue_size: avg_queue_size,
          most_queued_videos: most_queued
        }
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Series and season retention
  # ---------------------------------------------------------------------------

  @doc """
  Returns per-season completion stats for a series over the given period.

  Completion counts only `completed = true` progress rows whose
  `updated_at` falls inside the period window. A viewer is a "starter" if
  they completed any episode in the season; a "finisher" if they completed
  every episode. Out-of-order viewing is allowed.

  Returns a list of `%{season_id, season_number, title, episode_count,
  starters, finishers, completion_rate}` ordered by `season_number` ascending.

  Exempt from doctest — hits the database.
  """
  def list_season_stats(%Organization{} = org, %Series{} = series, period) do
    key = "analytics:series_seasons:#{series.id}:#{period}"

    Cache.fetch(key, [ttl: @cache_ttl], fn ->
      Bobine.Otel.with_span "bobine.analytics.list_season_stats",
                            %{
                              "bobine.org.id" => org.id,
                              "bobine.series.id" => series.id
                            } do
        from_dt = period_start_datetime(period)
        seasons = load_seasons_with_episodes(org.id, series.id)

        Enum.map(seasons, fn {season, episode_video_ids} ->
          stats = fetch_season_completion_stats(org.id, episode_video_ids, from_dt)

          %{
            season_id: season.id,
            season_number: season.season_number,
            title: season.title,
            episode_count: length(episode_video_ids),
            starters: stats.starters,
            finishers: stats.finishers,
            completion_rate: stats.completion_rate
          }
        end)
      end
    end)
  end

  @doc """
  Returns completion stats for a single season over the given period.

  Returns `%{starters, finishers, completion_rate, episode_count}`.

  Exempt from doctest — hits the database.
  """
  def season_completion_rate(%Organization{} = org, %Season{} = season, period) do
    Bobine.Otel.with_span "bobine.analytics.season_completion_rate",
                          %{"bobine.org.id" => org.id, "bobine.season.id" => season.id} do
      from_dt = period_start_datetime(period)
      episode_video_ids = fetch_season_episode_video_ids(org.id, season.id)
      stats = fetch_season_completion_stats(org.id, episode_video_ids, from_dt)

      Map.put(stats, :episode_count, length(episode_video_ids))
    end
  end

  defp load_seasons_with_episodes(org_id, series_id) do
    seasons =
      Season
      |> where([s], s.organization_id == ^org_id)
      |> where([s], s.series_id == ^series_id and is_nil(s.deleted_at))
      |> order_by([s], asc: s.season_number)
      |> Repo.all()

    season_ids = Enum.map(seasons, & &1.id)

    episodes_by_season =
      Episode
      |> where([e], e.organization_id == ^org_id and e.season_id in ^season_ids)
      |> select([e], {e.season_id, e.video_id})
      |> Repo.all()
      |> Enum.group_by(fn {season_id, _} -> season_id end, fn {_, video_id} -> video_id end)

    Enum.map(seasons, fn season ->
      {season, Map.get(episodes_by_season, season.id, [])}
    end)
  end

  defp fetch_season_episode_video_ids(org_id, season_id) do
    Episode
    |> where([e], e.organization_id == ^org_id and e.season_id == ^season_id)
    |> select([e], e.video_id)
    |> Repo.all()
  end

  @doc """
  Returns per-episode completion counts for a season over the given period.

  Each entry includes `episode_id, episode_number, title, video_id,
  completions`. Ordered by `episode_number` ascending. Used by the season
  analytics page to render the funnel chart.

  Exempt from doctest — hits the database.
  """
  def episode_funnel(%Organization{} = org, %Season{} = season, period) do
    Bobine.Otel.with_span "bobine.analytics.episode_funnel",
                          %{"bobine.org.id" => org.id, "bobine.season.id" => season.id} do
      from_dt = period_start_datetime(period)
      episodes = load_season_episodes(org.id, season.id)
      video_ids = Enum.map(episodes, & &1.video_id)

      completion_counts =
        if video_ids == [] do
          %{}
        else
          Progress
          |> where([p], p.organization_id == ^org.id)
          |> where([p], p.video_id in ^video_ids)
          |> where([p], p.completed == true and p.updated_at >= ^from_dt)
          |> where([p], not is_nil(p.viewer_id))
          |> group_by([p], p.video_id)
          |> select([p], {p.video_id, count(p.viewer_id, :distinct)})
          |> Repo.all()
          |> Map.new()
        end

      Enum.map(episodes, fn ep ->
        %{
          episode_id: ep.id,
          episode_number: ep.episode_number,
          video_id: ep.video_id,
          title: episode_display_title(ep),
          completions: Map.get(completion_counts, ep.video_id, 0)
        }
      end)
    end
  end

  @doc """
  Returns the rate at which viewers move from the current season to the
  next season in the series.

  Denominator: distinct viewers who completed the last episode of
  `season` within the period. Numerator: those viewers whose progress on
  the first episode of the next season reaches 25% of its duration.

  Returns `%{eligible, next_season_starters, rate, next_season_id}` where
  `next_season_id` is `nil` if there is no next season.

  Exempt from doctest — hits the database.
  """
  def next_season_start_rate(%Organization{} = org, %Season{} = season, period) do
    Bobine.Otel.with_span "bobine.analytics.next_season_start_rate",
                          %{"bobine.org.id" => org.id, "bobine.season.id" => season.id} do
      from_dt = period_start_datetime(period)

      with {:ok, next_season} <- load_next_season(org.id, season),
           {:ok, last_ep} <- load_last_episode(org.id, season.id),
           {:ok, first_next_ep, next_video} <-
             load_first_episode_with_video(org.id, next_season.id) do
        eligible_viewers =
          Progress
          |> where([p], p.organization_id == ^org.id)
          |> where([p], p.video_id == ^last_ep.video_id)
          |> where([p], p.completed == true and p.updated_at >= ^from_dt)
          |> where([p], not is_nil(p.viewer_id))
          |> select([p], p.viewer_id)
          |> distinct(true)
          |> Repo.all()

        eligible_count = length(eligible_viewers)
        threshold = (next_video.duration || 0.0) * 0.25

        next_starters =
          if eligible_count == 0 or threshold <= 0 do
            0
          else
            Progress
            |> where([p], p.organization_id == ^org.id)
            |> where([p], p.video_id == ^first_next_ep.video_id)
            |> where([p], p.viewer_id in ^eligible_viewers)
            |> where([p], p.position >= ^threshold)
            |> Repo.aggregate(:count, :viewer_id, distinct: true)
          end

        rate =
          if eligible_count > 0,
            do: Float.round(next_starters / eligible_count * 100, 1),
            else: 0.0

        %{
          eligible: eligible_count,
          next_season_starters: next_starters,
          rate: rate,
          next_season_id: next_season.id
        }
      else
        {:error, :no_next_season} ->
          %{eligible: 0, next_season_starters: 0, rate: 0.0, next_season_id: nil}

        {:error, _} ->
          %{eligible: 0, next_season_starters: 0, rate: 0.0, next_season_id: nil}
      end
    end
  end

  @doc """
  Returns the episode in a season where viewers most commonly drop off.

  A viewer "drops off" at episode N if they completed episode N within
  the period, did not finish the season, and did not start episode N+1
  within 7 days of completing N.

  Returns `%{episode_id, episode_number, title, drop_off_count}` or `nil`
  if there are no drop-offs.

  Exempt from doctest — hits the database.
  """
  def drop_off_episode(%Organization{} = org, %Season{} = season, period) do
    Bobine.Otel.with_span "bobine.analytics.drop_off_episode",
                          %{"bobine.org.id" => org.id, "bobine.season.id" => season.id} do
      from_dt = period_start_datetime(period)
      episodes = load_season_episodes(org.id, season.id)
      total_episodes = length(episodes)

      if total_episodes < 2 do
        nil
      else
        video_ids = Enum.map(episodes, & &1.video_id)
        video_id_to_episode = Map.new(episodes, &{&1.video_id, &1})

        rows =
          Progress
          |> where([p], p.organization_id == ^org.id)
          |> where([p], p.video_id in ^video_ids)
          |> where([p], p.updated_at >= ^from_dt)
          |> where([p], not is_nil(p.viewer_id))
          |> select([p], %{
            viewer_id: p.viewer_id,
            video_id: p.video_id,
            completed: p.completed,
            position: p.position,
            updated_at: p.updated_at
          })
          |> Repo.all()

        rows
        |> Enum.group_by(& &1.viewer_id)
        |> Enum.reduce(%{}, fn {_viewer, viewer_rows}, acc ->
          count_viewer_drop_off(
            viewer_rows,
            video_id_to_episode,
            episodes,
            total_episodes,
            acc
          )
        end)
        |> pick_worst_drop_off_episode(episodes)
      end
    end
  end

  defp pick_worst_drop_off_episode(counts, _episodes) when map_size(counts) == 0, do: nil

  defp pick_worst_drop_off_episode(counts, episodes) do
    {ep_num, drop_off_count} = Enum.max_by(counts, fn {_ep, count} -> count end)
    episode = Enum.find(episodes, &(&1.episode_number == ep_num))

    %{
      episode_id: episode.id,
      episode_number: episode.episode_number,
      title: episode_display_title(episode),
      drop_off_count: drop_off_count
    }
  end

  defp count_viewer_drop_off(viewer_rows, video_id_to_episode, episodes, total_episodes, acc) do
    last_completion = find_last_completion(viewer_rows, video_id_to_episode)

    if is_nil(last_completion) or last_completion.episode_number == total_episodes do
      acc
    else
      classify_viewer_drop_off(viewer_rows, episodes, last_completion, acc)
    end
  end

  defp find_last_completion(viewer_rows, video_id_to_episode) do
    viewer_rows
    |> Enum.filter(& &1.completed)
    |> case do
      [] ->
        nil

      completed ->
        completed
        |> Enum.map(fn row ->
          ep = Map.fetch!(video_id_to_episode, row.video_id)
          %{episode_number: ep.episode_number, updated_at: row.updated_at}
        end)
        |> Enum.max_by(& &1.episode_number)
    end
  end

  defp classify_viewer_drop_off(viewer_rows, episodes, last_completion, acc) do
    next_ep = Enum.find(episodes, &(&1.episode_number == last_completion.episode_number + 1))

    if next_ep && started_within_week?(viewer_rows, next_ep.video_id, last_completion.updated_at) do
      acc
    else
      Map.update(acc, last_completion.episode_number, 1, &(&1 + 1))
    end
  end

  defp started_within_week?(viewer_rows, next_video_id, last_completed_at) do
    cutoff = DateTime.add(last_completed_at, 7 * 86_400, :second)

    Enum.any?(viewer_rows, fn row ->
      row.video_id == next_video_id and row.position > 0.0 and
        DateTime.compare(row.updated_at, cutoff) in [:lt, :eq]
    end)
  end

  defp load_season_episodes(org_id, season_id) do
    Episode
    |> where([e], e.organization_id == ^org_id and e.season_id == ^season_id)
    |> order_by([e], asc: e.episode_number)
    |> Repo.all()
  end

  defp load_next_season(org_id, %Season{} = season) do
    next_number = season.season_number + 1

    Season
    |> where([s], s.organization_id == ^org_id and s.series_id == ^season.series_id)
    |> where([s], s.season_number == ^next_number and is_nil(s.deleted_at))
    |> Repo.one()
    |> case do
      nil -> {:error, :no_next_season}
      season -> {:ok, season}
    end
  end

  defp load_last_episode(org_id, season_id) do
    Episode
    |> where([e], e.organization_id == ^org_id and e.season_id == ^season_id)
    |> order_by([e], desc: e.episode_number)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :no_episode}
      episode -> {:ok, episode}
    end
  end

  defp load_first_episode_with_video(org_id, season_id) do
    result =
      Episode
      |> join(:inner, [e], v in Video, on: v.id == e.video_id)
      |> where([e, _v], e.organization_id == ^org_id and e.season_id == ^season_id)
      |> order_by([e, _v], asc: e.episode_number)
      |> limit(1)
      |> select([e, v], {e, v})
      |> Repo.one()

    case result do
      nil -> {:error, :no_episode}
      {episode, video} -> {:ok, episode, video}
    end
  end

  defp episode_display_title(%Episode{title: title, episode_number: num}) when is_binary(title) do
    if String.trim(title) == "", do: "Episode #{num}", else: title
  end

  defp episode_display_title(%Episode{episode_number: num}), do: "Episode #{num}"

  defp fetch_season_completion_stats(_org_id, [], _from_dt) do
    %{starters: 0, finishers: 0, completion_rate: 0.0}
  end

  defp fetch_season_completion_stats(org_id, episode_video_ids, from_dt) do
    episode_count = length(episode_video_ids)

    viewer_video_pairs =
      Progress
      |> where([p], p.organization_id == ^org_id)
      |> where([p], p.video_id in ^episode_video_ids)
      |> where([p], p.completed == true)
      |> where([p], p.updated_at >= ^from_dt)
      |> where([p], not is_nil(p.viewer_id))
      |> select([p], {p.viewer_id, p.video_id})
      |> distinct(true)
      |> Repo.all()

    by_viewer = Enum.group_by(viewer_video_pairs, &elem(&1, 0), &elem(&1, 1))
    starters = map_size(by_viewer)

    finishers =
      Enum.count(by_viewer, fn {_viewer, videos} ->
        length(videos) >= episode_count
      end)

    rate = if starters > 0, do: Float.round(finishers / starters * 100, 1), else: 0.0

    %{starters: starters, finishers: finishers, completion_rate: rate}
  end

  defp period_start_datetime(period) do
    DateTime.new!(period_start_date(period), ~T[00:00:00], "Etc/UTC")
  end

  # ---------------------------------------------------------------------------
  # Churn indicators
  # ---------------------------------------------------------------------------

  @doc """
  Returns churn indicators for the given period.

  Includes dunning count, cancellations, and trial conversion rate.

  Exempt from doctest — hits the database.
  """
  def get_churn_indicators(%Organization{} = org, period) do
    Bobine.Otel.with_span "bobine.analytics.get_churn_indicators",
                          %{"bobine.org.id" => org.id} do
      from_date = period_start_date(period)
      from_dt = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")

      dunning_count =
        ViewerSubscription
        |> where([s], s.organization_id == ^org.id and s.status == "past_due")
        |> where([s], is_nil(s.deleted_at))
        |> Repo.aggregate(:count, :id)

      cancellations =
        ViewerSubscription
        |> where([s], s.organization_id == ^org.id)
        |> where([s], not is_nil(s.canceled_at) and s.canceled_at >= ^from_dt)
        |> Repo.aggregate(:count, :id)

      trial_conversions = count_trial_conversions(org.id, from_date)
      trials_started = count_trials_started(org.id, from_date)

      trial_conversion_rate =
        if trials_started > 0,
          do: Float.round(trial_conversions / trials_started * 100, 1),
          else: 0.0

      %{
        dunning_count: dunning_count,
        cancellations_in_period: cancellations,
        trial_conversion_rate: trial_conversion_rate
      }
    end
  end

  # ---------------------------------------------------------------------------
  # Snapshot upsert (used by worker)
  # ---------------------------------------------------------------------------

  @doc """
  Upserts an analytics snapshot, idempotent on (org_id, period_date, metric_type).

  Returns `{:ok, snapshot}` or `{:error, :validation, changeset}`.

  Exempt from doctest — hits the database.
  """
  def upsert_snapshot(attrs) do
    Bobine.Otel.with_span "bobine.analytics.upsert_snapshot",
                          %{
                            "bobine.org.id" =>
                              Map.get(attrs, :organization_id, attrs["organization_id"])
                          } do
      changeset = Snapshot.changeset(%Snapshot{}, attrs)

      if changeset.valid? do
        result =
          Repo.insert(changeset,
            on_conflict: {:replace, [:value, :metadata, :updated_at]},
            conflict_target: [:organization_id, :period_date, :metric_type]
          )

        case result do
          {:ok, snapshot} ->
            Cache.delete_by_prefix("analytics:overview:#{snapshot.organization_id}")
            Cache.delete_by_prefix("analytics:engagement:#{snapshot.organization_id}")
            {:ok, snapshot}

          {:error, changeset} ->
            {:error, :validation, changeset}
        end
      else
        {:error, :validation, changeset}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp count_active_subscribers(org_id) do
    ViewerSubscription
    |> where([s], s.organization_id == ^org_id)
    |> where([s], s.status in ["active", "trialing"])
    |> where([s], is_nil(s.deleted_at))
    |> Repo.aggregate(:count, :id)
  end

  defp compute_mrr_cents(org_id) do
    active_subs =
      ViewerSubscription
      |> join(:inner, [s], p in Plan, on: s.plan_id == p.id)
      |> where([s, _p], s.organization_id == ^org_id)
      |> where([s, _p], s.status in ["active", "trialing"])
      |> where([s, _p], is_nil(s.deleted_at))
      |> select([s, p], %{amount: p.amount, interval: p.interval, fee: s.application_fee_percent})
      |> Repo.all()

    Enum.reduce(active_subs, 0, fn sub, acc ->
      net = sub.amount * (1 - Decimal.to_float(sub.fee) / 100)

      monthly =
        case sub.interval do
          :yearly -> net / 12
          _ -> net
        end

      acc + round(monthly)
    end)
  end

  defp count_views_in_period(org_id, period) do
    from_date = period_start_date(period)
    from_dt = DateTime.new!(from_date, Time.utc_now(), "Etc/UTC")

    Progress
    |> where([p], p.organization_id == ^org_id)
    |> where([p], p.position > 30.0)
    |> where([p], p.updated_at >= ^from_dt)
    |> select([p], {p.viewer_id, p.video_id})
    |> distinct(true)
    |> Repo.all()
    |> length()
  end

  defp compute_avg_watch_time(org_id, period) do
    from_date = period_start_date(period)
    from_dt = DateTime.new!(from_date, Time.utc_now(), "Etc/UTC")

    result =
      Progress
      |> where([p], p.organization_id == ^org_id and p.updated_at >= ^from_dt)
      |> where([p], not is_nil(p.duration) and p.duration > 0.0)
      |> Repo.aggregate(:avg, :position)

    case result do
      nil -> 0.0
      avg -> Float.round(to_float(avg), 1)
    end
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(n) when is_float(n), do: n

  defp count_viewers_with_progress(org_id, from_date) do
    from_dt = DateTime.new!(from_date, Time.utc_now(), "Etc/UTC")

    Progress
    |> where([p], p.organization_id == ^org_id and p.updated_at >= ^from_dt)
    |> select([p], p.viewer_id)
    |> distinct(true)
    |> Repo.all()
    |> length()
  end

  defp count_viewers_with_multiple_views(org_id, from_date) do
    from_dt = DateTime.new!(from_date, Time.utc_now(), "Etc/UTC")

    Progress
    |> where([p], p.organization_id == ^org_id and p.updated_at >= ^from_dt and p.position > 30.0)
    |> group_by([p], p.viewer_id)
    |> having([p], count(p.video_id) > 1)
    |> select([p], p.viewer_id)
    |> Repo.all()
    |> length()
  end

  defp count_viewers_with_queue(org_id) do
    QueueItem
    |> where([q], q.organization_id == ^org_id)
    |> select([q], q.viewer_id)
    |> distinct(true)
    |> Repo.all()
    |> length()
  end

  defp count_all_viewers(org_id) do
    alias Bobine.Viewers.Viewer

    Viewer
    |> where([v], v.organization_id == ^org_id and v.status == :active)
    |> Repo.aggregate(:count, :id)
  end

  defp compute_avg_queue_size(org_id) do
    result =
      QueueItem
      |> where([q], q.organization_id == ^org_id)
      |> group_by([q], q.viewer_id)
      |> select([q], count(q.id))
      |> Repo.all()

    case result do
      [] -> 0.0
      counts -> Float.round(Enum.sum(counts) / length(counts), 1)
    end
  end

  defp most_queued_videos(org_id) do
    QueueItem
    |> where([q], q.organization_id == ^org_id)
    |> join(:inner, [q], v in Video, on: q.video_id == v.id)
    |> group_by([q, v], [q.video_id, v.title])
    |> select([q, v], %{video_id: q.video_id, title: v.title, count: count(q.id)})
    |> order_by([q, _v], desc: count(q.id))
    |> limit(5)
    |> Repo.all()
  end

  defp count_trial_conversions(org_id, from_date) do
    from_dt = DateTime.new!(from_date, Time.utc_now(), "Etc/UTC")

    ViewerSubscription
    |> where([s], s.organization_id == ^org_id)
    |> where([s], s.status == "active")
    |> where([s], not is_nil(s.trial_end) and s.trial_end >= ^from_dt)
    |> Repo.aggregate(:count, :id)
  end

  defp count_trials_started(org_id, from_date) do
    from_dt = DateTime.new!(from_date, Time.utc_now(), "Etc/UTC")

    ViewerSubscription
    |> where([s], s.organization_id == ^org_id)
    |> where([s], not is_nil(s.trial_start) and s.trial_start >= ^from_dt)
    |> Repo.aggregate(:count, :id)
  end

  defp build_content_rows(org_id, video_ids, from_date, sort_by, sort_dir) do
    from_dt = DateTime.new!(from_date, Time.utc_now(), "Etc/UTC")

    metrics = %{
      titles: fetch_video_titles(video_ids),
      unique_viewers: fetch_unique_viewers(org_id, video_ids, from_dt),
      avg_watch_pct: fetch_avg_watch_pct(org_id, video_ids, from_dt),
      completion: fetch_completion_rates(org_id, video_ids, from_dt),
      watchlist: fetch_watchlist_counts(org_id, video_ids),
      favorites: fetch_favorite_counts(org_id, video_ids),
      top_drop_off: fetch_top_drop_offs(org_id, video_ids)
    }

    video_ids
    |> Enum.map(&assemble_content_row(&1, metrics))
    |> sort_rows(sort_by, sort_dir)
  end

  defp assemble_content_row(vid, metrics) do
    %{
      video_id: vid,
      title: Map.get(metrics.titles, vid, "Unknown"),
      unique_viewers: Map.get(metrics.unique_viewers, vid, 0),
      avg_watch_percentage: Map.get(metrics.avg_watch_pct, vid, 0.0),
      completion_rate: Map.get(metrics.completion, vid, 0.0),
      watchlist_adds: Map.get(metrics.watchlist, vid, 0),
      favorites: Map.get(metrics.favorites, vid, 0),
      top_drop_off: Map.get(metrics.top_drop_off, vid)
    }
  end

  defp fetch_top_drop_offs(org_id, video_ids) do
    VideoDropOffBucket
    |> where([b], b.organization_id == ^org_id and b.video_id in ^video_ids)
    |> Repo.all()
    |> Enum.group_by(& &1.video_id)
    |> Map.new(fn {video_id, rows} ->
      top = Enum.max_by(rows, & &1.count)

      {video_id,
       %{
         bucket: top.bucket,
         count: top.count,
         start_seconds: top.bucket * PlaybackDropOff.bucket_size(),
         end_seconds: (top.bucket + 1) * PlaybackDropOff.bucket_size()
       }}
    end)
  end

  defp fetch_video_titles(video_ids) do
    Video
    |> where([v], v.id in ^video_ids)
    |> select([v], {v.id, v.title})
    |> Repo.all()
    |> Map.new()
  end

  defp fetch_unique_viewers(org_id, video_ids, from_dt) do
    Progress
    |> where([p], p.organization_id == ^org_id and p.video_id in ^video_ids)
    |> where([p], p.position > 30.0 and p.updated_at >= ^from_dt)
    |> group_by([p], p.video_id)
    |> select([p], {p.video_id, count(p.id, :distinct)})
    |> Repo.all()
    |> Map.new()
  end

  defp fetch_avg_watch_pct(org_id, video_ids, from_dt) do
    Progress
    |> where(
      [p],
      p.organization_id == ^org_id and p.video_id in ^video_ids and p.updated_at >= ^from_dt
    )
    |> where([p], not is_nil(p.duration) and p.duration > 0.0)
    |> group_by([p], p.video_id)
    |> select([p], {p.video_id, avg(p.position / p.duration * 100)})
    |> Repo.all()
    |> Map.new(fn {id, avg} ->
      {id, if(avg, do: Float.round(to_float(avg), 1), else: 0.0)}
    end)
  end

  defp fetch_completion_rates(org_id, video_ids, from_dt) do
    Progress
    |> where(
      [p],
      p.organization_id == ^org_id and p.video_id in ^video_ids and p.updated_at >= ^from_dt
    )
    |> group_by([p], p.video_id)
    |> select(
      [p],
      {p.video_id, {count(p.id), sum(fragment("CASE WHEN ? THEN 1 ELSE 0 END", p.completed))}}
    )
    |> Repo.all()
    |> Map.new(fn {id, {total, completed}} ->
      rate =
        if total > 0,
          do: Float.round(to_float(completed || 0) / total * 100, 1),
          else: 0.0

      {id, rate}
    end)
  end

  defp fetch_watchlist_counts(org_id, video_ids) do
    WatchlistItem
    |> where([w], w.organization_id == ^org_id and w.video_id in ^video_ids)
    |> where([w], is_nil(w.deleted_at))
    |> group_by([w], w.video_id)
    |> select([w], {w.video_id, count(w.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp fetch_favorite_counts(org_id, video_ids) do
    Favorite
    |> where([f], f.organization_id == ^org_id and f.video_id in ^video_ids)
    |> where([f], is_nil(f.deleted_at))
    |> group_by([f], f.video_id)
    |> select([f], {f.video_id, count(f.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp sort_rows(rows, sort_by, :asc), do: Enum.sort_by(rows, &Map.get(&1, sort_by), :asc)
  defp sort_rows(rows, sort_by, _), do: Enum.sort_by(rows, &Map.get(&1, sort_by), :desc)

  defp period_start_date("7"), do: Date.add(Date.utc_today(), -7)
  defp period_start_date("30"), do: Date.add(Date.utc_today(), -30)
  defp period_start_date("90"), do: Date.add(Date.utc_today(), -90)

  defp period_start_date(days) when is_binary(days) do
    case Integer.parse(days) do
      {n, ""} -> Date.add(Date.utc_today(), -n)
      _ -> Date.add(Date.utc_today(), -30)
    end
  end

  defp period_start_date(_), do: Date.add(Date.utc_today(), -30)
end
