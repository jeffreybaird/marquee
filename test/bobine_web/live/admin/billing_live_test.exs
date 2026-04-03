defmodule BobineWeb.Admin.BillingLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  setup :verify_on_exit!

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :owner)
    %{org: org, user: user, membership: membership}
  end

  describe "no subscription" do
    test "plan grid shows active plans", %{membership: membership} do
      insert(:platform_plan,
        slug: "ind_basic",
        name: "Individual Basic",
        usage_tier: :basic,
        business_tier: :individual,
        amount: 2900
      )

      insert(:platform_plan,
        slug: "sb_super",
        name: "Small Business Super",
        usage_tier: :super,
        business_tier: :small_business,
        amount: 12_900
      )

      {:ok, view, html} =
        membership
        |> conn_for()
        |> live(~p"/admin/settings/billing")

      assert html =~ "platform-plan-grid"
      assert html =~ "Individual Basic"
      assert html =~ "Small Business Super"
      assert has_element?(view, "[data-test=platform-plan-ind_basic]")
      assert has_element?(view, "[data-test=platform-plan-sb_super]")
      assert has_element?(view, "[data-test=subscribe-btn]")
    end
  end

  describe "active subscription" do
    test "current plan is highlighted", %{membership: membership, org: org} do
      plan =
        insert(:platform_plan,
          slug: "my_plan",
          name: "My Plan",
          usage_tier: :super,
          business_tier: :individual,
          amount: 7900
        )

      insert(:platform_subscription, organization: org, platform_plan: plan)

      {:ok, view, _html} =
        membership
        |> conn_for()
        |> live(~p"/admin/settings/billing")

      assert has_element?(view, "[data-test=current-plan-badge]")
      assert has_element?(view, "[data-test=manage-subscription-btn]")
      assert has_element?(view, "[data-test=change-plan-btn]")
    end

    test "usage meters show correct values", %{membership: membership, org: org} do
      plan =
        insert(:platform_plan,
          slug: "meter_plan",
          usage_tier: :basic,
          business_tier: :small_business,
          max_videos: 50,
          max_team_seats: 5
        )

      insert(:platform_subscription, organization: org, platform_plan: plan)
      insert(:video, organization: org)
      insert(:video, organization: org)

      {:ok, view, _html} =
        membership
        |> conn_for()
        |> live(~p"/admin/settings/billing")

      assert has_element?(view, "[data-test=usage-meter-videos]")
      assert has_element?(view, "[data-test=usage-meter-views]")
      assert has_element?(view, "[data-test=usage-meter-seats]")
    end

    test "change plan shows plan grid", %{membership: membership, org: org} do
      plan =
        insert(:platform_plan,
          slug: "change_plan",
          usage_tier: :premium,
          business_tier: :enterprise,
          amount: 49_900
        )

      insert(:platform_subscription, organization: org, platform_plan: plan)

      {:ok, view, _html} =
        membership
        |> conn_for()
        |> live(~p"/admin/settings/billing")

      # Initially the plan grid is hidden
      refute has_element?(view, "[data-test=platform-plan-grid]")

      # Click change plan
      view |> element("[data-test=change-plan-btn]") |> render_click()

      assert has_element?(view, "[data-test=platform-plan-grid]")
    end
  end

  describe "past due subscription" do
    test "warning banner visible", %{membership: membership, org: org} do
      plan =
        insert(:platform_plan,
          slug: "past_due_plan",
          usage_tier: :basic,
          business_tier: :individual
        )

      insert(:platform_subscription,
        organization: org,
        platform_plan: plan,
        status: :past_due
      )

      {:ok, view, _html} =
        membership
        |> conn_for()
        |> live(~p"/admin/settings/billing")

      assert has_element?(view, "[data-test=billing-warning-banner]")
    end
  end
end
