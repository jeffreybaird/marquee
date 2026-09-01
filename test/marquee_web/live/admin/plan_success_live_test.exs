defmodule MarqueeWeb.Admin.PlanSuccessLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :owner)
    %{org: org, user: user, membership: membership}
  end

  describe "with active subscription" do
    test "shows success card and plan details", %{membership: membership, org: org} do
      plan =
        insert(:platform_plan,
          slug: "success_plan",
          name: "Pro Plan",
          usage_tier: :super,
          business_tier: :small_business,
          amount: 7900
        )

      insert(:platform_subscription, organization: org, platform_plan: plan)

      {:ok, view, html} =
        membership
        |> conn_for()
        |> live(~p"/admin/settings/billing/success")

      assert has_element?(view, "[data-test=plan-success-card]")
      assert has_element?(view, "[data-test=plan-details]")
      assert has_element?(view, "[data-test=plan-name]", "Pro Plan")
      assert has_element?(view, "[data-test=plan-amount]", "$79.00/mo")
      assert has_element?(view, "[data-test=next-billing-date]")
      assert has_element?(view, "[data-test=back-to-billing-link]")
      assert html =~ "Plan Updated"
    end

    test "back to billing link navigates correctly", %{membership: membership, org: org} do
      plan =
        insert(:platform_plan, slug: "nav_plan", usage_tier: :basic, business_tier: :individual)

      insert(:platform_subscription, organization: org, platform_plan: plan)

      {:ok, view, _html} =
        membership
        |> conn_for()
        |> live(~p"/admin/settings/billing/success")

      assert has_element?(view, "[data-test=back-to-billing-link]")

      {:ok, _view, html} =
        view
        |> element("[data-test=back-to-billing-link]")
        |> render_click()
        |> follow_redirect(conn_for(membership))

      assert html =~ "Billing"
    end
  end

  describe "without subscription" do
    test "shows success card without plan details", %{membership: membership} do
      {:ok, view, html} =
        membership
        |> conn_for()
        |> live(~p"/admin/settings/billing/success")

      assert has_element?(view, "[data-test=plan-success-card]")
      refute has_element?(view, "[data-test=plan-details]")
      assert html =~ "Plan Updated"
    end
  end
end
