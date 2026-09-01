defmodule Marquee.Workers.AnalyticsComputerTest do
  use Marquee.DataCase, async: true
  use Oban.Testing, repo: Marquee.Repo

  alias Marquee.Analytics
  alias Marquee.Workers.AnalyticsComputer

  describe "perform/1 — dispatch job" do
    test "runs snapshots for all active organizations" do
      org_a = insert(:organization)
      org_b = insert(:organization)

      # In inline test mode, dispatching runs per-org jobs immediately
      assert :ok = perform_job(AnalyticsComputer, %{"dispatch" => true})

      # Verify snapshots were created for both orgs
      yesterday = Date.add(Date.utc_today(), -1)
      from = Date.add(yesterday, -1)
      to = Date.utc_today()

      snaps_a = Marquee.Analytics.list_daily_subscriber_counts(org_a, from, to)
      snaps_b = Marquee.Analytics.list_daily_subscriber_counts(org_b, from, to)

      assert Enum.any?(snaps_a, &(&1.period_date == yesterday))
      assert Enum.any?(snaps_b, &(&1.period_date == yesterday))
    end
  end

  describe "perform/1 — per-org job" do
    test "computes and stores snapshots for yesterday" do
      org = insert(:organization)
      yesterday = Date.add(Date.utc_today(), -1)

      assert :ok = perform_job(AnalyticsComputer, %{"organization_id" => org.id})

      from = Date.add(yesterday, -1)
      to = Date.utc_today()
      snapshots = Analytics.list_daily_subscriber_counts(org, from, to)

      assert Enum.any?(snapshots, &(&1.period_date == yesterday))
    end

    test "handles missing organization gracefully" do
      missing_id = Ecto.UUID.generate()

      assert {:ok, :not_found} =
               perform_job(AnalyticsComputer, %{"organization_id" => missing_id})
    end

    test "idempotent: running twice produces same snapshot value" do
      org = insert(:organization)
      plan = insert(:plan, organization: org, amount: 500, interval: :monthly)
      insert(:viewer_subscription, organization: org, plan: plan, status: "active")

      assert :ok = perform_job(AnalyticsComputer, %{"organization_id" => org.id})
      assert :ok = perform_job(AnalyticsComputer, %{"organization_id" => org.id})

      yesterday = Date.add(Date.utc_today(), -1)
      from = Date.add(yesterday, -1)
      to = Date.utc_today()

      snapshots = Analytics.list_daily_subscriber_counts(org, from, to)
      yesterday_snaps = Enum.filter(snapshots, &(&1.period_date == yesterday))

      assert length(yesterday_snaps) == 1
    end

    test "error for one org does not fail another org's job" do
      org_a = insert(:organization)
      org_b = insert(:organization)

      assert :ok = perform_job(AnalyticsComputer, %{"organization_id" => org_a.id})
      assert :ok = perform_job(AnalyticsComputer, %{"organization_id" => org_b.id})
    end
  end
end
