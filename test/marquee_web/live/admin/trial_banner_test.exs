defmodule MarqueeWeb.Admin.TrialBannerTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp past, do: DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
  defp future, do: DateTime.utc_now() |> DateTime.add(5, :day) |> DateTime.truncate(:second)

  describe "trial banner in the admin layout" do
    test "shows the active-trial banner for an org within its trial window" do
      membership = insert(:membership, role: :owner)

      insert(:platform_subscription,
        organization: membership.organization,
        platform_plan: nil,
        stripe_subscription_id: nil,
        status: :trialing,
        trial_end: future()
      )

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin")

      assert html =~ ~s(data-test="trial-banner-active")
      assert html =~ "Free trial"
      refute html =~ ~s(data-test="trial-banner-expired")
    end

    test "shows the expired-trial banner once the window has elapsed" do
      membership = insert(:membership, role: :owner)

      insert(:platform_subscription,
        organization: membership.organization,
        platform_plan: nil,
        stripe_subscription_id: nil,
        status: :past_due,
        trial_end: past()
      )

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin")

      assert html =~ ~s(data-test="trial-banner-expired")
      assert html =~ "trial has ended"
      refute html =~ ~s(data-test="trial-banner-active")
    end

    test "shows no trial banner for a paid subscription" do
      membership = insert(:membership, role: :owner)
      insert(:platform_subscription, organization: membership.organization, status: :active)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin")

      refute html =~ ~s(data-test="trial-banner-active")
      refute html =~ ~s(data-test="trial-banner-expired")
    end
  end
end
