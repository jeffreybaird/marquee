defmodule Bobine.Billing.ViewerBillingTest do
  use Bobine.DataCase, async: true

  import Mox

  alias Bobine.Billing
  alias Bobine.Billing.{Coupon, ViewerSubscription}

  setup :verify_on_exit!

  defp connected_org do
    insert(:organization,
      stripe_connect_account_id: "acct_test_123",
      stripe_connect_onboarding_complete: true
    )
  end

  defp disconnected_org do
    insert(:organization,
      stripe_connect_account_id: nil,
      stripe_connect_onboarding_complete: false
    )
  end

  # ── Connect onboarding ─────────────────────────────────────────────────

  describe "initiate_connect_onboarding/1" do
    test "returns Stripe URL for org without existing account" do
      org = disconnected_org()

      expect(Bobine.Billing.MockStripeClient, :create_connect_account, fn params ->
        assert params.type == :standard
        {:ok, %{id: "acct_new_123"}}
      end)

      expect(Bobine.Billing.MockStripeClient, :create_connect_account_link, fn account_id,
                                                                               params ->
        assert account_id == "acct_new_123"
        assert params.return_url =~ "/admin/settings/stripe/return"
        {:ok, %{url: "https://connect.stripe.com/setup/123"}}
      end)

      assert {:ok, url} = Billing.initiate_connect_onboarding(org)
      assert url == "https://connect.stripe.com/setup/123"
    end

    test "reuses existing account ID if already set" do
      org = insert(:organization, stripe_connect_account_id: "acct_existing")

      expect(Bobine.Billing.MockStripeClient, :create_connect_account_link, fn "acct_existing",
                                                                               _params ->
        {:ok, %{url: "https://connect.stripe.com/setup/existing"}}
      end)

      assert {:ok, url} = Billing.initiate_connect_onboarding(org)
      assert url == "https://connect.stripe.com/setup/existing"
    end
  end

  describe "complete_connect_onboarding/2" do
    test "stores account ID and sets onboarding complete flag" do
      org = insert(:organization, stripe_connect_account_id: "acct_test")

      assert {:ok, updated_org} = Billing.complete_connect_onboarding(org, "acct_test")
      assert updated_org.stripe_connect_account_id == "acct_test"
      assert updated_org.stripe_connect_onboarding_complete == true
    end
  end

  describe "ensure_stripe_connected/1" do
    test "returns :ok for connected org" do
      org = connected_org()
      assert :ok = Billing.ensure_stripe_connected(org)
    end

    test "returns error for disconnected org" do
      org = disconnected_org()
      assert {:error, :stripe_not_connected} = Billing.ensure_stripe_connected(org)
    end
  end

  # ── Plan management with Stripe ────────────────────────────────────────

  describe "create_plan_with_stripe/2" do
    test "creates Stripe Product + Price and inserts plan" do
      org = connected_org()

      expect(Bobine.Billing.MockStripeClient, :create_connected_product, fn params, opts ->
        assert params.name == "Premium"
        assert opts[:connect_account] == "acct_test_123"
        {:ok, %{id: "prod_test"}}
      end)

      expect(Bobine.Billing.MockStripeClient, :create_connected_price, fn params, opts ->
        assert params.product == "prod_test"
        assert params.unit_amount == 999
        assert opts[:connect_account] == "acct_test_123"
        {:ok, %{id: "price_test"}}
      end)

      attrs = %{name: "Premium", amount: 999, interval: :monthly}
      assert {:ok, plan} = Billing.create_plan_with_stripe(org, attrs)
      assert plan.name == "Premium"
      assert plan.stripe_product_id == "prod_test"
      assert plan.stripe_price_id == "price_test"
      assert plan.amount == 999
      assert plan.organization_id == org.id
    end

    test "returns error when Stripe not connected" do
      org = disconnected_org()

      attrs = %{name: "Premium", amount: 999, interval: :monthly}
      assert {:error, :stripe_not_connected} = Billing.create_plan_with_stripe(org, attrs)
    end
  end

  describe "update_plan_with_stripe/3" do
    test "creates new Stripe Price when price changes" do
      org = connected_org()
      plan = insert(:plan, organization: org, amount: 999)

      expect(Bobine.Billing.MockStripeClient, :create_connected_price, fn _params, opts ->
        assert opts[:connect_account] == "acct_test_123"
        {:ok, %{id: "price_new_test"}}
      end)

      assert {:ok, updated} = Billing.update_plan_with_stripe(org, plan, %{amount: 1299})
      assert updated.amount == 1299
      assert updated.stripe_price_id == "price_new_test"
    end

    test "does not create new Price when only name changes" do
      org = connected_org()
      plan = insert(:plan, organization: org)

      assert {:ok, updated} = Billing.update_plan_with_stripe(org, plan, %{name: "New Name"})
      assert updated.name == "New Name"
      assert updated.stripe_price_id == plan.stripe_price_id
    end
  end

  describe "list_plans/2" do
    test "returns active plans ordered by position" do
      org = connected_org()
      _plan1 = insert(:plan, organization: org, name: "A", position: 1)
      _plan2 = insert(:plan, organization: org, name: "B", position: 0)
      _deleted = insert(:plan, organization: org, name: "Deleted", deleted_at: DateTime.utc_now())

      %{results: plans} = Billing.list_plans(org)
      assert length(plans) == 2
    end

    test "plans scoped to org (tenant isolation)" do
      org_a = connected_org()
      org_b = connected_org()
      _plan_a = insert(:plan, organization: org_a, name: "Plan A")
      _plan_b = insert(:plan, organization: org_b, name: "Plan B")

      %{results: plans} = Billing.list_plans(org_a)
      assert length(plans) == 1
      assert hd(plans).name == "Plan A"
    end
  end

  describe "deactivate_plan/1 and reactivate_plan/1" do
    test "deactivate sets active to false" do
      org = connected_org()
      plan = insert(:plan, organization: org, active: true)

      assert {:ok, deactivated} = Billing.deactivate_plan(plan)
      assert deactivated.active == false
    end

    test "reactivate sets active to true" do
      org = connected_org()
      plan = insert(:plan, organization: org, active: false)

      assert {:ok, reactivated} = Billing.reactivate_plan(plan)
      assert reactivated.active == true
    end
  end

  # ── Coupons ────────────────────────────────────────────────────────────

  describe "create_coupon/2" do
    test "creates Stripe coupon + promo code and inserts locally" do
      org = connected_org()

      expect(Bobine.Billing.MockStripeClient, :create_connected_coupon, fn params, opts ->
        assert params.percent_off
        assert opts[:connect_account] == "acct_test_123"
        {:ok, %{id: "coupon_test"}}
      end)

      expect(Bobine.Billing.MockStripeClient, :create_connected_promotion_code, fn params, opts ->
        assert params.coupon == "coupon_test"
        assert params.code == "LAUNCH50"
        assert opts[:connect_account] == "acct_test_123"
        {:ok, %{id: "promo_test"}}
      end)

      attrs = %{code: "launch50", name: "Launch", percent_off: Decimal.new("50"), duration: :once}
      assert {:ok, coupon} = Billing.create_coupon(org, attrs)
      assert coupon.code == "LAUNCH50"
      assert coupon.stripe_coupon_id == "coupon_test"
      assert coupon.stripe_promotion_code_id == "promo_test"
    end

    test "returns error when Stripe not connected" do
      org = disconnected_org()
      attrs = %{code: "TEST", name: "Test", percent_off: Decimal.new("10"), duration: :once}
      assert {:error, :stripe_not_connected} = Billing.create_coupon(org, attrs)
    end
  end

  describe "list_coupons/2" do
    test "scoped to org" do
      org_a = connected_org()
      org_b = connected_org()

      insert_coupon(org_a, "CODE_A")
      insert_coupon(org_b, "CODE_B")

      %{results: coupons} = Billing.list_coupons(org_a)
      assert length(coupons) == 1
      assert hd(coupons).code == "CODE_A"
    end
  end

  describe "deactivate_coupon/1" do
    test "sets active to false" do
      org = connected_org()
      coupon = insert_coupon(org, "DEACTIVATE_ME")

      assert {:ok, deactivated} = Billing.deactivate_coupon(coupon)
      assert deactivated.active == false
    end
  end

  # ── Checkout ───────────────────────────────────────────────────────────

  describe "create_viewer_checkout/3" do
    test "returns checkout session with 2% application fee" do
      org = connected_org()
      viewer = insert(:viewer, organization: org)
      plan = insert(:plan, organization: org)

      expect(Bobine.Billing.MockStripeClient, :create_connected_checkout_session, fn params ->
        assert params[:stripe_connect_account_id] == "acct_test_123"
        assert params[:viewer_email] == viewer.email
        assert params[:line_items] == [%{price: plan.stripe_price_id, quantity: 1}]
        {:ok, %{url: "https://checkout.stripe.com/session_123", id: "cs_test"}}
      end)

      assert {:ok, session} = Billing.create_viewer_checkout(org, viewer, plan)
      assert session.url == "https://checkout.stripe.com/session_123"
    end

    test "returns error when Stripe not connected" do
      org = disconnected_org()
      viewer = insert(:viewer, organization: org)
      plan = insert(:plan, organization: org)

      assert {:error, :stripe_not_connected} = Billing.create_viewer_checkout(org, viewer, plan)
    end

    test "passes trial_period_days from plan" do
      org = connected_org()
      viewer = insert(:viewer, organization: org)
      plan = insert(:plan, organization: org, trial_period_days: 14)

      expect(Bobine.Billing.MockStripeClient, :create_connected_checkout_session, fn params ->
        assert params[:trial_period_days] == 14
        {:ok, %{url: "https://checkout.stripe.com/session_trial", id: "cs_trial"}}
      end)

      assert {:ok, _session} = Billing.create_viewer_checkout(org, viewer, plan)
    end
  end

  # ── Subscription lifecycle ─────────────────────────────────────────────

  describe "create_subscription_from_checkout/3" do
    test "creates ViewerSubscription record" do
      org = connected_org()
      viewer = insert(:viewer, organization: org)

      session = %{
        "subscription" => "sub_test_123",
        "customer" => "cus_test_123"
      }

      assert {:ok, sub} = Billing.create_subscription_from_checkout(org, viewer, session)
      assert sub.stripe_subscription_id == "sub_test_123"
      assert sub.stripe_customer_id == "cus_test_123"
      assert sub.status == "active"
      assert sub.viewer_id == viewer.id
      assert sub.organization_id == org.id
    end
  end

  describe "activate_viewer_subscription/3" do
    test "sets viewer to active when no trial" do
      org = connected_org()
      viewer = insert(:viewer, organization: org)
      sub = %ViewerSubscription{trial_end: nil}

      Billing.activate_viewer_subscription(org, viewer, sub)
      updated = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert updated.subscription_status == "active"
    end

    test "sets viewer to trial when trial present" do
      org = connected_org()
      viewer = insert(:viewer, organization: org)
      trial_end = DateTime.add(DateTime.utc_now(), 14, :day) |> DateTime.truncate(:second)
      sub = %ViewerSubscription{trial_end: trial_end}

      Billing.activate_viewer_subscription(org, viewer, sub)
      updated = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert updated.subscription_status == "trial"
    end
  end

  describe "mark_payment_failed/3" do
    test "sets viewer and subscription to past_due" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      sub = insert_viewer_subscription(org, viewer)

      assert :ok = Billing.mark_payment_failed(org, viewer, sub)

      updated_viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert updated_viewer.subscription_status == "past_due"

      updated_sub = Repo.get!(ViewerSubscription, sub.id)
      assert updated_sub.status == "past_due"
    end
  end

  describe "mark_payment_succeeded/3" do
    test "restores active status when was past_due" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "past_due")
      sub = insert_viewer_subscription(org, viewer, status: "past_due")

      assert :ok = Billing.mark_payment_succeeded(org, viewer, sub)

      updated_viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert updated_viewer.subscription_status == "active"
    end

    test "does nothing when already active" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      sub = insert_viewer_subscription(org, viewer)

      assert :ok = Billing.mark_payment_succeeded(org, viewer, sub)

      updated_viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert updated_viewer.subscription_status == "active"
    end
  end

  describe "cancel_subscription_from_stripe/3" do
    test "sets viewer and subscription to canceled" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      sub = insert_viewer_subscription(org, viewer)

      assert :ok = Billing.cancel_subscription_from_stripe(org, viewer, sub)

      updated_viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert updated_viewer.subscription_status == "canceled"

      updated_sub = Repo.get!(ViewerSubscription, sub.id)
      assert updated_sub.status == "canceled"
      assert updated_sub.canceled_at != nil
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────

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

  defp insert_viewer_subscription(org, viewer, attrs \\ []) do
    %ViewerSubscription{}
    |> ViewerSubscription.changeset(
      Enum.into(attrs, %{
        organization_id: org.id,
        viewer_id: viewer.id,
        stripe_subscription_id: "sub_#{System.unique_integer([:positive])}",
        stripe_customer_id: "cus_test",
        status: "active"
      })
    )
    |> Repo.insert!()
  end
end
