defmodule Bobine.Admin.AnalyticsTest do
  use Bobine.DataCase, async: true

  alias Bobine.Admin
  alias Bobine.Repo

  # Uses a process-local counter so consecutive calls within the same test
  # don't collide on the unique (usage_tier, business_tier) constraint.
  defp insert_platform_plan(amount) do
    count = Process.get(:plan_counter, 0)
    Process.put(:plan_counter, count + 1)
    n = System.unique_integer([:positive])

    all_combos =
      for u <- [:basic, :super, :premium],
          b <- [:individual, :small_business, :enterprise],
          do: {u, b}

    {usage_tier, business_tier} = Enum.at(all_combos, rem(count, 9))

    Repo.insert!(%Bobine.Billing.PlatformPlan{
      name: "Test Plan #{n}",
      slug: "test-plan-#{n}",
      amount: amount,
      usage_tier: usage_tier,
      business_tier: business_tier,
      transaction_fee_percent: 5.0
    })
  end

  defp now_truncated, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp insert_platform_subscription(org, plan, status) do
    n = System.unique_integer([:positive])

    Repo.insert!(%Bobine.Billing.PlatformSubscription{
      organization_id: org.id,
      platform_plan_id: plan.id,
      stripe_subscription_id: "sub_test_#{n}",
      stripe_customer_id: "cus_test_#{n}",
      status: status,
      inserted_at: now_truncated(),
      updated_at: now_truncated()
    })
  end

  describe "platform_overview/0" do
    test "returns correct org count excluding deleted" do
      insert(:organization)
      deleted = insert(:organization)
      {:ok, _} = Admin.delete_organization(deleted)

      result = Admin.platform_overview()
      assert result.total_orgs >= 1
    end

    test "returns zero platform_mrr_cents when no active platform subscriptions" do
      result = Admin.platform_overview()
      assert result.platform_mrr_cents == 0
    end

    test "sums active platform subscription plan amounts" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      plan_a = insert_platform_plan(4900)
      plan_b = insert_platform_plan(9900)
      insert_platform_subscription(org_a, plan_a, :active)
      insert_platform_subscription(org_b, plan_b, :active)

      result = Admin.platform_overview()
      assert result.platform_mrr_cents >= 4900 + 9900
    end

    test "does not count canceled platform subscriptions in mrr" do
      org = insert(:organization)
      plan = insert_platform_plan(4900)
      insert_platform_subscription(org, plan, :canceled)

      result = Admin.platform_overview()
      assert result.platform_mrr_cents == 0
    end

    test "sums viewer fee revenue from active viewer subscriptions" do
      org = insert(:organization)
      plan = insert(:plan, organization: org, amount: 1000)

      insert(:viewer_subscription,
        organization: org,
        plan: plan,
        status: "active",
        application_fee_percent: Decimal.new("10")
      )

      result = Admin.platform_overview()
      assert result.viewer_fee_revenue_cents >= 100
    end

    test "returns zero viewer_fee_revenue_cents when no active viewer subscriptions" do
      result = Admin.platform_overview()
      assert result.viewer_fee_revenue_cents == 0
    end
  end

  describe "list_organizations_with_health/1" do
    test "returns all non-deleted orgs" do
      org_a = insert(:organization)
      org_b = insert(:organization)

      result = Admin.list_organizations_with_health()

      ids = Enum.map(result.results, & &1.id)
      assert org_a.id in ids
      assert org_b.id in ids
    end

    test "does not return deleted orgs" do
      deleted = insert(:organization)
      {:ok, _} = Admin.delete_organization(deleted)

      result = Admin.list_organizations_with_health()
      ids = Enum.map(result.results, & &1.id)
      refute deleted.id in ids
    end

    test "filters by search (name ILIKE)" do
      insert(:organization, name: "Alpha Studio", slug: "alpha-studio")
      insert(:organization, name: "Beta Channel", slug: "beta-channel")

      result = Admin.list_organizations_with_health(search: "Alpha")
      assert length(result.results) == 1
      assert hd(result.results).name == "Alpha Studio"
    end

    test "returns empty results when no orgs match search" do
      insert(:organization, name: "Alpha Studio", slug: "alpha-studio")
      result = Admin.list_organizations_with_health(search: "zzz-no-match")
      assert result.results == []
    end

    test "each result has required health fields" do
      org = insert(:organization)

      result = Admin.list_organizations_with_health(search: org.name)
      row = hd(result.results)

      assert Map.has_key?(row, :id)
      assert Map.has_key?(row, :name)
      assert Map.has_key?(row, :platform_plan_name)
      assert Map.has_key?(row, :subscriber_count)
      assert Map.has_key?(row, :mrr_cents)
      assert Map.has_key?(row, :video_count)
      assert Map.has_key?(row, :active_viewers_last_7d)
      assert Map.has_key?(row, :status)
    end

    test "subscriber_count reflects active subscriptions for that org" do
      org = insert(:organization)
      other_org = insert(:organization)
      insert(:viewer, organization: org, subscription_status: "active")
      insert(:viewer, organization: org, subscription_status: "active")
      insert(:viewer, organization: other_org, subscription_status: "active")

      result = Admin.list_organizations_with_health(search: org.name)
      row = hd(result.results)
      assert row.subscriber_count == 2
    end

    test "video_count reflects videos for that org" do
      org = insert(:organization)
      insert(:video, organization: org)
      insert(:video, organization: org)

      result = Admin.list_organizations_with_health(search: org.name)
      row = hd(result.results)
      assert row.video_count == 2
    end

    test "sorts by name ascending by default" do
      insert(:organization, name: "Zebra Corp", slug: "zebra-corp")
      insert(:organization, name: "Alpha Inc", slug: "alpha-inc")

      result = Admin.list_organizations_with_health()
      names = Enum.map(result.results, & &1.name)

      alpha_idx = Enum.find_index(names, &(&1 == "Alpha Inc"))
      zebra_idx = Enum.find_index(names, &(&1 == "Zebra Corp"))
      assert alpha_idx < zebra_idx
    end

    test "sorts by name descending" do
      insert(:organization, name: "Zebra Corp", slug: "zebra-corp-2")
      insert(:organization, name: "Alpha Inc", slug: "alpha-inc-2")

      result = Admin.list_organizations_with_health(sort_by: :name, sort_dir: :desc)
      names = Enum.map(result.results, & &1.name)

      zebra_idx = Enum.find_index(names, &(&1 == "Zebra Corp"))
      alpha_idx = Enum.find_index(names, &(&1 == "Alpha Inc"))
      assert zebra_idx < alpha_idx
    end

    test "paginates results" do
      for i <- 1..5 do
        insert(:organization,
          name: "Org #{String.pad_leading("#{i}", 2, "0")}",
          slug: "org-pag-#{i}"
        )
      end

      page1 = Admin.list_organizations_with_health(per_page: 2, page: 1)
      page2 = Admin.list_organizations_with_health(per_page: 2, page: 2)

      assert length(page1.results) == 2
      assert page1.page == 1
      assert page1.per_page == 2
      assert page1.total >= 5
      assert page1.total_pages >= 3

      ids1 = MapSet.new(page1.results, & &1.id)
      ids2 = MapSet.new(page2.results, & &1.id)
      assert MapSet.disjoint?(ids1, ids2)
    end

    test "returns pagination metadata" do
      result = Admin.list_organizations_with_health()
      assert Map.has_key?(result, :results)
      assert Map.has_key?(result, :page)
      assert Map.has_key?(result, :per_page)
      assert Map.has_key?(result, :total)
      assert Map.has_key?(result, :total_pages)
    end
  end

  describe "list_daily_platform_mrr/2" do
    test "returns a list with one entry per day in range" do
      from = ~D[2024-01-01]
      to = ~D[2024-01-07]

      result = Admin.list_daily_platform_mrr(from, to)
      assert length(result) == 7
    end

    test "each entry has date and mrr_cents fields" do
      result = Admin.list_daily_platform_mrr(~D[2024-01-01], ~D[2024-01-01])
      entry = hd(result)
      assert Map.has_key?(entry, :date)
      assert Map.has_key?(entry, :mrr_cents)
    end

    test "returns zero mrr for days with no active subscriptions" do
      result = Admin.list_daily_platform_mrr(~D[2020-01-01], ~D[2020-01-03])
      Enum.each(result, fn entry -> assert entry.mrr_cents == 0 end)
    end

    test "counts active platform subscription on each day in range" do
      org = insert(:organization)
      plan = insert_platform_plan(5000)
      n = System.unique_integer([:positive])

      Repo.insert!(%Bobine.Billing.PlatformSubscription{
        organization_id: org.id,
        platform_plan_id: plan.id,
        stripe_subscription_id: "sub_mrr_#{n}",
        stripe_customer_id: "cus_mrr_#{n}",
        status: :active,
        inserted_at: ~U[2024-02-15 00:00:00Z],
        updated_at: ~U[2024-02-15 00:00:00Z]
      })

      result = Admin.list_daily_platform_mrr(~D[2024-02-15], ~D[2024-02-17])
      Enum.each(result, fn entry -> assert entry.mrr_cents == 5000 end)
    end
  end

  describe "list_new_org_signups/2" do
    test "returns one entry per day in range" do
      from = ~D[2024-03-01]
      to = ~D[2024-03-05]

      result = Admin.list_new_org_signups(from, to)
      assert length(result) == 5
    end

    test "each entry has date and count fields" do
      result = Admin.list_new_org_signups(~D[2024-03-01], ~D[2024-03-01])
      entry = hd(result)
      assert Map.has_key?(entry, :date)
      assert Map.has_key?(entry, :count)
    end

    test "counts organizations inserted on a given date" do
      from = ~D[2024-04-01]
      to = ~D[2024-04-03]

      dt = ~U[2024-04-02 10:00:00Z]

      Bobine.Repo.insert!(%Bobine.Accounts.Organization{
        name: "Signup Test Org",
        slug: "signup-test-org-#{System.unique_integer([:positive])}",
        inserted_at: dt,
        updated_at: dt
      })

      result = Admin.list_new_org_signups(from, to)
      apr2 = Enum.find(result, &(&1.date == ~D[2024-04-02]))
      assert apr2.count >= 1
    end

    test "returns zero for days with no signups in that range" do
      result = Admin.list_new_org_signups(~D[2000-01-01], ~D[2000-01-02])
      Enum.each(result, fn entry -> assert entry.count == 0 end)
    end
  end
end
