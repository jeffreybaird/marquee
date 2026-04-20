defmodule Bobine.AnalyticsTest do
  use Bobine.DataCase, async: true

  alias Bobine.Analytics

  # ---------------------------------------------------------------------------
  # get_overview_cards/2
  # ---------------------------------------------------------------------------

  describe "get_overview_cards/2" do
    test "returns zero counts for org with no data" do
      org = insert(:organization)
      result = Analytics.get_overview_cards(org, "30")

      assert result.active_subscribers == 0
      assert result.mrr_cents == 0
      assert result.total_views == 0
      assert result.avg_watch_time_seconds == 0.0
    end

    test "counts active and trialing subscribers" do
      org = insert(:organization)
      plan = insert(:plan, organization: org, amount: 1000, interval: :monthly)

      insert(:viewer_subscription, organization: org, plan: plan, status: "active")
      insert(:viewer_subscription, organization: org, plan: plan, status: "trialing")
      insert(:viewer_subscription, organization: org, plan: plan, status: "canceled")

      result = Analytics.get_overview_cards(org, "30")
      assert result.active_subscribers == 2
    end

    test "org A cannot see org B's subscribers" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      plan_b = insert(:plan, organization: org_b, amount: 1000, interval: :monthly)
      insert(:viewer_subscription, organization: org_b, plan: plan_b, status: "active")

      result = Analytics.get_overview_cards(org_a, "30")
      assert result.active_subscribers == 0
    end

    test "computes MRR from active subscriptions" do
      org = insert(:organization)
      plan = insert(:plan, organization: org, amount: 1000, interval: :monthly)

      insert(:viewer_subscription,
        organization: org,
        plan: plan,
        status: "active",
        application_fee_percent: Decimal.new("0")
      )

      result = Analytics.get_overview_cards(org, "30")
      assert result.mrr_cents == 1000
    end

    test "counts views for short videos using percentage threshold" do
      org = insert(:organization)
      video = insert(:video, organization: org, duration: 15.0)
      viewer = insert(:subscribed_viewer, organization: org)

      insert(:progress,
        organization: org,
        video: video,
        viewer: viewer,
        position: 5.0,
        duration: 15.0
      )

      result = Analytics.get_overview_cards(org, "30")
      assert result.total_views == 1
    end

    test "does not count trivial views below 10% threshold" do
      org = insert(:organization)
      video = insert(:video, organization: org, duration: 100.0)
      viewer = insert(:subscribed_viewer, organization: org)

      insert(:progress,
        organization: org,
        video: video,
        viewer: viewer,
        position: 5.0,
        duration: 100.0
      )

      result = Analytics.get_overview_cards(org, "30")
      assert result.total_views == 0
    end

    test "computes avg watch time from float position column without crashing" do
      org = insert(:organization)
      video = insert(:video, organization: org)

      insert(:progress,
        organization: org,
        video: video,
        position: 60.0,
        duration: 120.0
      )

      insert(:progress,
        organization: org,
        video: video,
        user: build(:user),
        position: 90.0,
        duration: 120.0
      )

      result = Analytics.get_overview_cards(org, "30")

      assert is_float(result.avg_watch_time_seconds)
      assert result.avg_watch_time_seconds == 75.0
    end
  end

  # ---------------------------------------------------------------------------
  # list_daily_subscriber_counts/3
  # ---------------------------------------------------------------------------

  describe "list_daily_subscriber_counts/3" do
    test "returns empty list when no snapshots exist" do
      org = insert(:organization)
      from = Date.add(Date.utc_today(), -7)
      to = Date.utc_today()

      result = Analytics.list_daily_subscriber_counts(org, from, to)
      assert is_list(result)
    end

    test "returns snapshots within date range" do
      org = insert(:organization)
      yesterday = Date.add(Date.utc_today(), -1)

      insert(:analytics_snapshot,
        organization: org,
        period_date: yesterday,
        metric_type: "daily_subscribers",
        value: Decimal.new("5")
      )

      from = Date.add(Date.utc_today(), -7)
      to = Date.utc_today()
      result = Analytics.list_daily_subscriber_counts(org, from, to)

      assert Enum.any?(result, &(&1.period_date == yesterday))
    end

    test "org A cannot see org B's subscriber snapshots" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      yesterday = Date.add(Date.utc_today(), -1)

      insert(:analytics_snapshot,
        organization: org_b,
        period_date: yesterday,
        metric_type: "daily_subscribers",
        value: Decimal.new("99")
      )

      from = Date.add(Date.utc_today(), -7)
      to = Date.add(Date.utc_today(), -1)
      result = Analytics.list_daily_subscriber_counts(org_a, from, to)

      refute Enum.any?(result, &(Decimal.to_integer(&1.value) == 99))
    end

    test "appends live count for today" do
      org = insert(:organization)
      plan = insert(:plan, organization: org, amount: 999, interval: :monthly)
      insert(:viewer_subscription, organization: org, plan: plan, status: "active")

      from = Date.add(Date.utc_today(), -7)
      to = Date.utc_today()
      result = Analytics.list_daily_subscriber_counts(org, from, to)

      today_entry = Enum.find(result, &(&1.period_date == Date.utc_today()))
      assert today_entry != nil
    end
  end

  # ---------------------------------------------------------------------------
  # list_daily_revenue/3
  # ---------------------------------------------------------------------------

  describe "list_daily_revenue/3" do
    test "returns revenue snapshots within date range" do
      org = insert(:organization)
      yesterday = Date.add(Date.utc_today(), -1)

      insert(:analytics_snapshot,
        organization: org,
        period_date: yesterday,
        metric_type: "daily_revenue",
        value: Decimal.new("5000")
      )

      from = Date.add(Date.utc_today(), -7)
      to = Date.utc_today()
      result = Analytics.list_daily_revenue(org, from, to)

      assert Enum.any?(result, &(&1.period_date == yesterday))
    end

    test "tenant isolation: org A cannot see org B revenue" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      yesterday = Date.add(Date.utc_today(), -1)

      insert(:analytics_snapshot,
        organization: org_b,
        period_date: yesterday,
        metric_type: "daily_revenue",
        value: Decimal.new("99999")
      )

      from = Date.add(Date.utc_today(), -7)
      to = Date.utc_today()
      result = Analytics.list_daily_revenue(org_a, from, to)

      refute Enum.any?(result, &(Decimal.to_integer(&1.value) == 99_999))
    end
  end

  # ---------------------------------------------------------------------------
  # list_content_performance/3
  # ---------------------------------------------------------------------------

  describe "list_content_performance/3" do
    test "returns empty results when org has no videos" do
      org = insert(:organization)
      result = Analytics.list_content_performance(org, "30")
      assert result.results == []
      assert result.total == 0
    end

    test "returns paginated content rows" do
      org = insert(:organization)
      _videos = for _ <- 1..5, do: insert(:video, organization: org)

      result = Analytics.list_content_performance(org, "30", per_page: 3)
      assert length(result.results) <= 3
      assert result.per_page == 3
      assert result.total == 5
      assert result.total_pages == 2
    end

    test "pagination metadata is correct" do
      org = insert(:organization)
      for _ <- 1..10, do: insert(:video, organization: org)

      page1 = Analytics.list_content_performance(org, "30", per_page: 5, page: 1)
      page2 = Analytics.list_content_performance(org, "30", per_page: 5, page: 2)

      assert page1.page == 1
      assert page2.page == 2
      assert length(page1.results) == 5
      assert length(page2.results) == 5
    end

    test "per_page capped at 100" do
      org = insert(:organization)
      result = Analytics.list_content_performance(org, "30", per_page: 200)
      assert result.per_page == 100
    end

    test "tenant isolation: org A cannot see org B videos" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      insert(:video, organization: org_b, title: "Org B Secret Video")

      result = Analytics.list_content_performance(org_a, "30")
      refute Enum.any?(result.results, &(&1.title == "Org B Secret Video"))
    end

    test "sortable by different columns" do
      org = insert(:organization)
      insert(:video, organization: org)
      insert(:video, organization: org)

      for col <- [:unique_viewers, :completion_rate, :watchlist_adds, :favorites] do
        result = Analytics.list_content_performance(org, "30", sort_by: col, sort_dir: :desc)
        assert is_list(result.results)
      end
    end

    test "includes top drop-off bucket per row" do
      org = insert(:organization)
      video = insert(:video, organization: org)

      insert(:video_drop_off_bucket,
        organization: org,
        video: video,
        bucket: 3,
        count: 2
      )

      insert(:video_drop_off_bucket,
        organization: org,
        video: video,
        bucket: 8,
        count: 7
      )

      result = Analytics.list_content_performance(org, "30")
      row = Enum.find(result.results, &(&1.video_id == video.id))

      assert row.top_drop_off.bucket == 8
      assert row.top_drop_off.count == 7
      assert row.top_drop_off.start_seconds == 80
      assert row.top_drop_off.end_seconds == 90
    end

    test "top_drop_off is nil when video has no drop-off data" do
      org = insert(:organization)
      video = insert(:video, organization: org)

      result = Analytics.list_content_performance(org, "30")
      row = Enum.find(result.results, &(&1.video_id == video.id))

      assert row.top_drop_off == nil
    end

    test "computes avg watch percentage from float progress without crashing" do
      org = insert(:organization)
      video = insert(:video, organization: org)

      insert(:progress,
        organization: org,
        video: video,
        position: 60.0,
        duration: 120.0
      )

      insert(:progress,
        organization: org,
        video: video,
        user: build(:user),
        position: 30.0,
        duration: 120.0
      )

      result = Analytics.list_content_performance(org, "30")
      row = Enum.find(result.results, &(&1.video_id == video.id))

      assert row
      assert is_float(row.avg_watch_percentage)
      assert row.avg_watch_percentage == 37.5
    end
  end

  # ---------------------------------------------------------------------------
  # get_engagement_metrics/2
  # ---------------------------------------------------------------------------

  describe "get_engagement_metrics/2" do
    test "returns zeroed engagement for org with no data" do
      org = insert(:organization)
      result = Analytics.get_engagement_metrics(org, "30")

      assert result.continue_watching_conversion_rate == 0.0
      assert result.queue_usage_percent == 0.0
      assert result.avg_queue_size == 0.0
      assert result.most_queued_videos == []
    end

    test "tenant isolation: org A engagement excludes org B data" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      viewer_b = insert(:viewer, organization: org_b)
      video_b = insert(:video, organization: org_b)

      insert(:queue_item,
        organization: org_b,
        viewer: viewer_b,
        video: video_b
      )

      result = Analytics.get_engagement_metrics(org_a, "30")
      assert result.queue_usage_percent == 0.0
    end
  end

  # ---------------------------------------------------------------------------
  # get_churn_indicators/2
  # ---------------------------------------------------------------------------

  describe "get_churn_indicators/2" do
    test "returns zeros for org with no subscriptions" do
      org = insert(:organization)
      result = Analytics.get_churn_indicators(org, "30")

      assert result.dunning_count == 0
      assert result.cancellations_in_period == 0
      assert result.trial_conversion_rate == 0.0
    end

    test "counts past_due subscriptions as dunning" do
      org = insert(:organization)
      insert(:viewer_subscription, organization: org, status: "past_due")

      result = Analytics.get_churn_indicators(org, "30")
      assert result.dunning_count == 1
    end

    test "tenant isolation: dunning only for own org" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      insert(:viewer_subscription, organization: org_b, status: "past_due")

      result = Analytics.get_churn_indicators(org_a, "30")
      assert result.dunning_count == 0
    end
  end

  # ---------------------------------------------------------------------------
  # get_video_watch_stats/2
  # ---------------------------------------------------------------------------

  describe "get_video_watch_stats/2" do
    test "returns zero counts for video with no progress" do
      org = insert(:organization)
      video = insert(:video, organization: org)

      result = Analytics.get_video_watch_stats(org, video.id)

      assert result.unique_viewers == 0
      assert result.avg_watch_percentage == 0.0
    end

    test "counts unique viewers with position > 30s" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      viewer_a = insert(:subscribed_viewer, organization: org)
      viewer_b = insert(:subscribed_viewer, organization: org)

      insert(:progress,
        organization: org,
        video: video,
        viewer: viewer_a,
        position: 60.0,
        duration: 120.0
      )

      insert(:progress,
        organization: org,
        video: video,
        viewer: viewer_b,
        position: 45.0,
        duration: 120.0
      )

      result = Analytics.get_video_watch_stats(org, video.id)
      assert result.unique_viewers == 2
    end

    test "excludes viewers with position <= 30s" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      viewer = insert(:subscribed_viewer, organization: org)

      insert(:progress,
        organization: org,
        video: video,
        viewer: viewer,
        position: 10.0,
        duration: 120.0
      )

      result = Analytics.get_video_watch_stats(org, video.id)
      assert result.unique_viewers == 0
    end

    test "computes avg watch percentage" do
      org = insert(:organization)
      video = insert(:video, organization: org)

      insert(:progress,
        organization: org,
        video: video,
        user: build(:user),
        position: 60.0,
        duration: 120.0
      )

      insert(:progress,
        organization: org,
        video: video,
        user: build(:user),
        position: 120.0,
        duration: 120.0
      )

      result = Analytics.get_video_watch_stats(org, video.id)
      assert result.avg_watch_percentage == 75.0
    end

    test "org A cannot see org B video stats" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      video_b = insert(:video, organization: org_b)
      viewer = insert(:subscribed_viewer, organization: org_b)

      insert(:progress,
        organization: org_b,
        video: video_b,
        viewer: viewer,
        position: 60.0,
        duration: 120.0
      )

      result = Analytics.get_video_watch_stats(org_a, video_b.id)
      assert result.unique_viewers == 0
    end
  end

  # ---------------------------------------------------------------------------
  # drop_off_distribution/2 and top_drop_off_buckets_by_video/2
  # ---------------------------------------------------------------------------

  describe "drop_off_distribution/2" do
    test "returns empty distribution when video has no drop-offs" do
      org = insert(:organization)
      video = insert(:video, organization: org)

      result = Analytics.drop_off_distribution(org, video.id)

      assert result.total == 0
      assert result.buckets == []
    end

    test "returns per-bucket counts and percentages" do
      org = insert(:organization)
      video = insert(:video, organization: org)

      insert(:video_drop_off_bucket, organization: org, video: video, bucket: 2, count: 1)
      insert(:video_drop_off_bucket, organization: org, video: video, bucket: 5, count: 3)

      result = Analytics.drop_off_distribution(org, video.id)

      assert result.total == 4

      [b2, b5] = result.buckets
      assert b2.bucket == 2
      assert b2.count == 1
      assert b2.start_seconds == 20
      assert b2.end_seconds == 30
      assert b2.percentage == 25.0

      assert b5.bucket == 5
      assert b5.count == 3
      assert b5.percentage == 75.0
    end

    test "tenant isolation: org A cannot see org B drop-offs" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      video_a = insert(:video, organization: org_a)
      video_b = insert(:video, organization: org_b)

      insert(:video_drop_off_bucket,
        organization: org_b,
        video: video_b,
        bucket: 3,
        count: 99
      )

      result = Analytics.drop_off_distribution(org_a, video_a.id)
      assert result.total == 0
      assert result.buckets == []
    end
  end

  describe "top_drop_off_buckets_by_video/2" do
    test "returns the worst bucket per video" do
      org = insert(:organization)
      video_a = insert(:video, organization: org)
      video_b = insert(:video, organization: org)

      insert(:video_drop_off_bucket, organization: org, video: video_a, bucket: 1, count: 2)
      insert(:video_drop_off_bucket, organization: org, video: video_a, bucket: 7, count: 9)
      insert(:video_drop_off_bucket, organization: org, video: video_b, bucket: 4, count: 4)

      result = Analytics.top_drop_off_buckets_by_video(org, [video_a.id, video_b.id])

      assert result[video_a.id].bucket == 7
      assert result[video_a.id].count == 9
      assert result[video_a.id].start_seconds == 70
      assert result[video_a.id].end_seconds == 80
      assert result[video_b.id].bucket == 4
    end

    test "videos with no drop-offs are absent from the result" do
      org = insert(:organization)
      video = insert(:video, organization: org)

      assert Analytics.top_drop_off_buckets_by_video(org, [video.id]) == %{}
    end

    test "returns empty map for empty video_ids list" do
      org = insert(:organization)
      assert Analytics.top_drop_off_buckets_by_video(org, []) == %{}
    end

    test "tenant isolation: org A cannot see org B top buckets" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      video_b = insert(:video, organization: org_b)

      insert(:video_drop_off_bucket,
        organization: org_b,
        video: video_b,
        bucket: 2,
        count: 50
      )

      result = Analytics.top_drop_off_buckets_by_video(org_a, [video_b.id])
      assert result == %{}
    end
  end

  # ---------------------------------------------------------------------------
  # Series retention
  # ---------------------------------------------------------------------------

  describe "list_season_stats/3" do
    test "returns empty list for a series with no seasons" do
      org = insert(:organization)
      series = insert(:series, organization: org)

      assert Analytics.list_season_stats(org, series, "30") == []
    end

    test "returns zeroed stats for a season with no viewing activity" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)
      video = insert(:video, organization: org)
      insert(:episode, organization: org, season: season, video: video, episode_number: 1)

      [stats] = Analytics.list_season_stats(org, series, "30")

      assert stats.season_id == season.id
      assert stats.episode_count == 1
      assert stats.starters == 0
      assert stats.finishers == 0
      assert stats.completion_rate == 0.0
    end

    test "counts a viewer who completed every episode as a finisher" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)

      video1 = insert(:video, organization: org)
      video2 = insert(:video, organization: org)
      insert(:episode, organization: org, season: season, video: video1, episode_number: 1)
      insert(:episode, organization: org, season: season, video: video2, episode_number: 2)

      viewer = insert(:viewer, organization: org)

      insert(:progress,
        organization: org,
        video: video1,
        viewer: viewer,
        user: nil,
        completed: true,
        position: 0.0
      )

      insert(:progress,
        organization: org,
        video: video2,
        viewer: viewer,
        user: nil,
        completed: true,
        position: 0.0
      )

      [stats] = Analytics.list_season_stats(org, series, "30")

      assert stats.starters == 1
      assert stats.finishers == 1
      assert stats.completion_rate == 100.0
    end

    test "counts a partial-completion viewer as a starter but not a finisher" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)

      video1 = insert(:video, organization: org)
      video2 = insert(:video, organization: org)
      insert(:episode, organization: org, season: season, video: video1, episode_number: 1)
      insert(:episode, organization: org, season: season, video: video2, episode_number: 2)

      viewer = insert(:viewer, organization: org)

      insert(:progress,
        organization: org,
        video: video1,
        viewer: viewer,
        user: nil,
        completed: true,
        position: 0.0
      )

      [stats] = Analytics.list_season_stats(org, series, "30")
      assert stats.starters == 1
      assert stats.finishers == 0
      assert stats.completion_rate == 0.0
    end

    test "ignores out-of-period completions" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)
      video = insert(:video, organization: org)
      insert(:episode, organization: org, season: season, video: video, episode_number: 1)

      old_timestamp = DateTime.add(DateTime.utc_now(), -120 * 86_400, :second)

      insert(:progress,
        organization: org,
        video: video,
        viewer: build(:viewer, organization: org),
        user: nil,
        completed: true,
        position: 0.0,
        updated_at: old_timestamp
      )

      [stats] = Analytics.list_season_stats(org, series, "30")
      assert stats.starters == 0
      assert stats.finishers == 0
    end

    test "out-of-order viewing still counts viewers for both episodes" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)

      video1 = insert(:video, organization: org)
      video2 = insert(:video, organization: org)
      insert(:episode, organization: org, season: season, video: video1, episode_number: 1)
      insert(:episode, organization: org, season: season, video: video2, episode_number: 2)

      viewer = insert(:viewer, organization: org)

      insert(:progress,
        organization: org,
        video: video2,
        viewer: viewer,
        user: nil,
        completed: true,
        position: 0.0
      )

      insert(:progress,
        organization: org,
        video: video1,
        viewer: viewer,
        user: nil,
        completed: true,
        position: 0.0
      )

      [stats] = Analytics.list_season_stats(org, series, "30")
      assert stats.finishers == 1
    end

    test "tenant isolation: org A cannot see org B series stats" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      series_b = insert(:series, organization: org_b)
      season_b = insert(:season, organization: org_b, series: series_b, season_number: 1)
      video_b = insert(:video, organization: org_b)
      insert(:episode, organization: org_b, season: season_b, video: video_b, episode_number: 1)

      insert(:progress,
        organization: org_b,
        video: video_b,
        viewer: build(:viewer, organization: org_b),
        user: nil,
        completed: true,
        position: 0.0
      )

      # Fetching with org_a returns [] because the series does not belong to org_a
      assert Analytics.list_season_stats(org_a, series_b, "30") == []
    end

    test "orders seasons by season_number ascending" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      insert(:season, organization: org, series: series, season_number: 3, title: "S3")
      insert(:season, organization: org, series: series, season_number: 1, title: "S1")
      insert(:season, organization: org, series: series, season_number: 2, title: "S2")

      stats = Analytics.list_season_stats(org, series, "30")
      assert Enum.map(stats, & &1.season_number) == [1, 2, 3]
    end
  end

  describe "season_completion_rate/3" do
    test "returns zeros for a season with no episodes" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)

      result = Analytics.season_completion_rate(org, season, "30")
      assert result.starters == 0
      assert result.finishers == 0
      assert result.completion_rate == 0.0
      assert result.episode_count == 0
    end

    test "computes rate from multiple viewers" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)

      video1 = insert(:video, organization: org)
      video2 = insert(:video, organization: org)
      insert(:episode, organization: org, season: season, video: video1, episode_number: 1)
      insert(:episode, organization: org, season: season, video: video2, episode_number: 2)

      viewer_a = insert(:viewer, organization: org)
      viewer_b = insert(:viewer, organization: org)

      # viewer_a finishes both
      insert(:progress,
        organization: org,
        video: video1,
        viewer: viewer_a,
        user: nil,
        completed: true,
        position: 0.0
      )

      insert(:progress,
        organization: org,
        video: video2,
        viewer: viewer_a,
        user: nil,
        completed: true,
        position: 0.0
      )

      # viewer_b only finishes the first
      insert(:progress,
        organization: org,
        video: video1,
        viewer: viewer_b,
        user: nil,
        completed: true,
        position: 0.0
      )

      result = Analytics.season_completion_rate(org, season, "30")
      assert result.starters == 2
      assert result.finishers == 1
      assert result.completion_rate == 50.0
      assert result.episode_count == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Episode funnel + next-season start + drop-off episode
  # ---------------------------------------------------------------------------

  describe "episode_funnel/3" do
    test "returns zero completions for a season with no data" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)
      video = insert(:video, organization: org)
      insert(:episode, organization: org, season: season, video: video, episode_number: 1)

      [row] = Analytics.episode_funnel(org, season, "30")
      assert row.completions == 0
      assert row.episode_number == 1
    end

    test "returns per-episode distinct-viewer completion counts" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)
      video1 = insert(:video, organization: org)
      video2 = insert(:video, organization: org)
      insert(:episode, organization: org, season: season, video: video1, episode_number: 1)
      insert(:episode, organization: org, season: season, video: video2, episode_number: 2)

      viewer_a = insert(:viewer, organization: org)
      viewer_b = insert(:viewer, organization: org)

      insert(:progress,
        organization: org,
        video: video1,
        viewer: viewer_a,
        user: nil,
        completed: true,
        position: 0.0
      )

      insert(:progress,
        organization: org,
        video: video1,
        viewer: viewer_b,
        user: nil,
        completed: true,
        position: 0.0
      )

      insert(:progress,
        organization: org,
        video: video2,
        viewer: viewer_a,
        user: nil,
        completed: true,
        position: 0.0
      )

      rows = Analytics.episode_funnel(org, season, "30")
      assert [%{episode_number: 1, completions: 2}, %{episode_number: 2, completions: 1}] = rows
    end

    test "orders episodes by episode_number ascending" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)

      insert(:episode,
        organization: org,
        season: season,
        video: insert(:video, organization: org),
        episode_number: 3
      )

      insert(:episode,
        organization: org,
        season: season,
        video: insert(:video, organization: org),
        episode_number: 1
      )

      insert(:episode,
        organization: org,
        season: season,
        video: insert(:video, organization: org),
        episode_number: 2
      )

      rows = Analytics.episode_funnel(org, season, "30")
      assert Enum.map(rows, & &1.episode_number) == [1, 2, 3]
    end
  end

  describe "next_season_start_rate/3" do
    test "returns nil next_season_id when series has only one season" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)

      insert(:episode,
        organization: org,
        season: season,
        video: insert(:video, organization: org),
        episode_number: 1
      )

      result = Analytics.next_season_start_rate(org, season, "30")
      assert result.next_season_id == nil
      assert result.eligible == 0
    end

    test "computes rate when viewers advance to 25% of next season" do
      org = insert(:organization)
      series = insert(:series, organization: org)

      season1 = insert(:season, organization: org, series: series, season_number: 1)
      season2 = insert(:season, organization: org, series: series, season_number: 2)

      s1_final = insert(:video, organization: org)
      s2_first = insert(:video, organization: org, duration: 1000.0)

      insert(:episode, organization: org, season: season1, video: s1_final, episode_number: 1)
      insert(:episode, organization: org, season: season2, video: s2_first, episode_number: 1)

      viewer_a = insert(:viewer, organization: org)
      viewer_b = insert(:viewer, organization: org)

      # Both viewers completed the last episode of season 1
      for viewer <- [viewer_a, viewer_b] do
        insert(:progress,
          organization: org,
          video: s1_final,
          viewer: viewer,
          user: nil,
          completed: true,
          position: 0.0
        )
      end

      # Only viewer_a reached 25% of season 2 ep1
      insert(:progress,
        organization: org,
        video: s2_first,
        viewer: viewer_a,
        user: nil,
        completed: false,
        position: 300.0,
        duration: 1000.0
      )

      insert(:progress,
        organization: org,
        video: s2_first,
        viewer: viewer_b,
        user: nil,
        completed: false,
        position: 50.0,
        duration: 1000.0
      )

      result = Analytics.next_season_start_rate(org, season1, "30")
      assert result.eligible == 2
      assert result.next_season_starters == 1
      assert result.rate == 50.0
      assert result.next_season_id == season2.id
    end

    test "returns zero rate when no viewers completed current season" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season1 = insert(:season, organization: org, series: series, season_number: 1)
      season2 = insert(:season, organization: org, series: series, season_number: 2)

      insert(:episode,
        organization: org,
        season: season1,
        video: insert(:video, organization: org),
        episode_number: 1
      )

      insert(:episode,
        organization: org,
        season: season2,
        video: insert(:video, organization: org, duration: 500.0),
        episode_number: 1
      )

      result = Analytics.next_season_start_rate(org, season1, "30")
      assert result.eligible == 0
      assert result.rate == 0.0
    end
  end

  describe "drop_off_episode/3" do
    test "returns nil when season has fewer than two episodes" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)

      insert(:episode,
        organization: org,
        season: season,
        video: insert(:video, organization: org),
        episode_number: 1
      )

      assert Analytics.drop_off_episode(org, season, "30") == nil
    end

    test "identifies the episode where viewers most commonly stop" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)

      videos = for _ <- 1..4, do: insert(:video, organization: org)

      Enum.with_index(videos, 1)
      |> Enum.each(fn {video, number} ->
        insert(:episode, organization: org, season: season, video: video, episode_number: number)
      end)

      two_weeks_ago = DateTime.add(DateTime.utc_now(), -14 * 86_400, :second)

      # Viewers 1, 2, 3 all complete episodes 1 and 2 but don't start episode 3
      for _ <- 1..3 do
        viewer = insert(:viewer, organization: org)

        insert(:progress,
          organization: org,
          video: Enum.at(videos, 0),
          viewer: viewer,
          user: nil,
          completed: true,
          position: 0.0,
          updated_at: two_weeks_ago
        )

        insert(:progress,
          organization: org,
          video: Enum.at(videos, 1),
          viewer: viewer,
          user: nil,
          completed: true,
          position: 0.0,
          updated_at: two_weeks_ago
        )
      end

      # Viewer 4 completes everything (not a drop-off)
      viewer_4 = insert(:viewer, organization: org)

      for video <- videos do
        insert(:progress,
          organization: org,
          video: video,
          viewer: viewer_4,
          user: nil,
          completed: true,
          position: 0.0
        )
      end

      result = Analytics.drop_off_episode(org, season, "30")
      assert result.episode_number == 2
      assert result.drop_off_count == 3
    end

    test "excludes viewers who started the next episode within a week" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1)

      video1 = insert(:video, organization: org)
      video2 = insert(:video, organization: org)
      video3 = insert(:video, organization: org)

      insert(:episode, organization: org, season: season, video: video1, episode_number: 1)
      insert(:episode, organization: org, season: season, video: video2, episode_number: 2)
      insert(:episode, organization: org, season: season, video: video3, episode_number: 3)

      viewer = insert(:viewer, organization: org)

      # Completed episode 2 three days ago
      three_days_ago = DateTime.add(DateTime.utc_now(), -3 * 86_400, :second)

      insert(:progress,
        organization: org,
        video: video2,
        viewer: viewer,
        user: nil,
        completed: true,
        position: 0.0,
        updated_at: three_days_ago
      )

      # Started episode 3 two days ago (within a week)
      two_days_ago = DateTime.add(DateTime.utc_now(), -2 * 86_400, :second)

      insert(:progress,
        organization: org,
        video: video3,
        viewer: viewer,
        user: nil,
        completed: false,
        position: 12.0,
        updated_at: two_days_ago
      )

      assert Analytics.drop_off_episode(org, season, "30") == nil
    end
  end

  # ---------------------------------------------------------------------------
  # upsert_snapshot/1
  # ---------------------------------------------------------------------------

  describe "upsert_snapshot/1" do
    test "creates a new snapshot" do
      org = insert(:organization)

      attrs = %{
        organization_id: org.id,
        period_date: ~D[2026-01-01],
        metric_type: "daily_views",
        value: Decimal.new("42")
      }

      assert {:ok, snapshot} = Analytics.upsert_snapshot(attrs)
      assert snapshot.organization_id == org.id
      assert snapshot.metric_type == "daily_views"
    end

    test "upsert is idempotent — running twice yields same result" do
      org = insert(:organization)

      attrs = %{
        organization_id: org.id,
        period_date: ~D[2026-01-01],
        metric_type: "daily_subscribers",
        value: Decimal.new("10")
      }

      assert {:ok, _} = Analytics.upsert_snapshot(attrs)
      assert {:ok, snap2} = Analytics.upsert_snapshot(attrs)
      assert Decimal.to_integer(snap2.value) == 10
    end

    test "upsert updates value on conflict" do
      org = insert(:organization)

      attrs = %{
        organization_id: org.id,
        period_date: ~D[2026-01-01],
        metric_type: "daily_revenue",
        value: Decimal.new("100")
      }

      {:ok, _} = Analytics.upsert_snapshot(attrs)
      {:ok, updated} = Analytics.upsert_snapshot(%{attrs | value: Decimal.new("200")})
      assert Decimal.to_integer(updated.value) == 200
    end

    test "returns validation error for invalid metric_type" do
      org = insert(:organization)

      attrs = %{
        organization_id: org.id,
        period_date: ~D[2026-01-01],
        metric_type: "bad_metric",
        value: Decimal.new("1")
      }

      assert {:error, :validation, changeset} = Analytics.upsert_snapshot(attrs)
      refute changeset.valid?
    end
  end
end
