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
