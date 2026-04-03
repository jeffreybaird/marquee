defmodule Bobine.Billing.MultiTenantIsolationTest do
  use Bobine.DataCase, async: true

  alias Bobine.Billing
  alias Bobine.Billing.{Coupon, ViewerSubscription}

  defp connected_org do
    insert(:organization,
      stripe_connect_account_id: "acct_#{System.unique_integer([:positive])}",
      stripe_connect_onboarding_complete: true
    )
  end

  describe "plan isolation" do
    test "list_plans only returns org's plans" do
      org_a = connected_org()
      org_b = connected_org()

      insert(:plan, organization: org_a, name: "A")
      insert(:plan, organization: org_b, name: "B")

      %{results: plans_a} = Billing.list_plans(org_a)
      %{results: plans_b} = Billing.list_plans(org_b)

      assert Enum.all?(plans_a, &(&1.organization_id == org_a.id))
      assert Enum.all?(plans_b, &(&1.organization_id == org_b.id))
      assert length(plans_a) == 1
      assert length(plans_b) == 1
    end

    test "get_plan! only returns org's plan" do
      org_a = connected_org()
      org_b = connected_org()

      plan_a = insert(:plan, organization: org_a)
      _plan_b = insert(:plan, organization: org_b)

      assert Billing.get_plan!(org_a, plan_a.id).id == plan_a.id

      assert_raise Ecto.NoResultsError, fn ->
        Billing.get_plan!(org_b, plan_a.id)
      end
    end
  end

  describe "coupon isolation" do
    test "list_coupons only returns org's coupons" do
      org_a = connected_org()
      org_b = connected_org()

      insert_coupon(org_a, "CODE_A")
      insert_coupon(org_b, "CODE_B")

      %{results: coupons_a} = Billing.list_coupons(org_a)
      %{results: coupons_b} = Billing.list_coupons(org_b)

      assert length(coupons_a) == 1
      assert hd(coupons_a).code == "CODE_A"

      assert length(coupons_b) == 1
      assert hd(coupons_b).code == "CODE_B"
    end
  end

  describe "viewer subscription isolation" do
    test "get_viewer_subscription_by_stripe_id scoped to org" do
      org_a = connected_org()
      org_b = connected_org()

      viewer_a = insert(:viewer, organization: org_a)
      viewer_b = insert(:viewer, organization: org_b)

      sub_a = insert_viewer_subscription(org_a, viewer_a, "sub_a")
      _sub_b = insert_viewer_subscription(org_b, viewer_b, "sub_b")

      assert {:ok, found} = Billing.get_viewer_subscription_by_stripe_id(org_a, "sub_a")
      assert found.id == sub_a.id

      assert {:error, :not_found} = Billing.get_viewer_subscription_by_stripe_id(org_b, "sub_a")
    end
  end

  defp insert_coupon(org, code) do
    %Coupon{}
    |> Coupon.changeset(%{
      organization_id: org.id,
      code: code,
      name: code,
      percent_off: Decimal.new("10"),
      duration: :once,
      stripe_coupon_id: "coupon_#{code}",
      stripe_promotion_code_id: "promo_#{code}",
      active: true
    })
    |> Repo.insert!()
  end

  defp insert_viewer_subscription(org, viewer, stripe_sub_id) do
    %ViewerSubscription{}
    |> ViewerSubscription.changeset(%{
      organization_id: org.id,
      viewer_id: viewer.id,
      stripe_subscription_id: stripe_sub_id,
      status: "active"
    })
    |> Repo.insert!()
  end
end
