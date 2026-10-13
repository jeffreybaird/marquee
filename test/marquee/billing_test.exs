defmodule Marquee.BillingTest do
  use Marquee.DataCase

  import Mox

  alias Marquee.Billing

  describe "plans" do
    alias Marquee.Billing.Plan

    import Marquee.BillingFixtures

    @invalid_attrs %{
      active: nil,
      name: nil,
      stripe_price_id: nil,
      stripe_product_id: nil,
      amount: nil,
      interval: nil
    }

    setup do
      %{org: insert(:organization)}
    end

    test "list_plans/2 returns plans for the given org" do
      plan = plan_fixture()
      org = Marquee.Repo.preload(plan, :organization).organization
      assert %{results: [^plan]} = Billing.list_plans(org)
    end

    test "get_plan!/2 returns the plan with given id" do
      plan = plan_fixture()
      org = Marquee.Repo.preload(plan, :organization).organization
      assert Billing.get_plan!(org, plan.id).id == plan.id
    end

    test "create_plan/1 with valid data creates a plan", %{org: org} do
      valid_attrs = %{
        active: true,
        name: "some name",
        stripe_price_id: "some stripe_price_id",
        stripe_product_id: "some stripe_product_id",
        amount: 42,
        interval: :monthly,
        organization_id: org.id
      }

      assert {:ok, %Plan{} = plan} = Billing.create_plan(valid_attrs)
      assert plan.active == true
      assert plan.name == "some name"
      assert plan.stripe_price_id == "some stripe_price_id"
      assert plan.stripe_product_id == "some stripe_product_id"
      assert plan.amount == 42
      assert plan.interval == :monthly
    end

    test "create_plan/1 with invalid data returns error changeset" do
      assert {:error, :validation, %Ecto.Changeset{}} = Billing.create_plan(@invalid_attrs)
    end

    test "update_plan/2 with valid data updates the plan" do
      plan = plan_fixture()

      update_attrs = %{
        active: false,
        name: "some updated name",
        stripe_price_id: "some updated stripe_price_id",
        stripe_product_id: "some updated stripe_product_id",
        amount: 43,
        interval: :yearly
      }

      assert {:ok, %Plan{} = plan} = Billing.update_plan(plan, update_attrs)
      assert plan.active == false
      assert plan.name == "some updated name"
      assert plan.stripe_price_id == "some updated stripe_price_id"
      assert plan.stripe_product_id == "some updated stripe_product_id"
      assert plan.amount == 43
      assert plan.interval == :yearly
    end

    test "update_plan/2 with invalid data returns error changeset" do
      plan = plan_fixture()
      org = Marquee.Repo.preload(plan, :organization).organization
      assert {:error, :validation, %Ecto.Changeset{}} = Billing.update_plan(plan, @invalid_attrs)
      assert plan.id == Billing.get_plan!(org, plan.id).id
    end

    test "delete_plan/1 soft-deletes the plan" do
      plan = plan_fixture()
      org = Marquee.Repo.preload(plan, :organization).organization
      assert {:ok, %Plan{} = deleted} = Billing.delete_plan(plan)
      assert deleted.deleted_at != nil
      assert %{results: []} = Billing.list_plans(org)
    end

    test "restore_plan/1 restores a soft-deleted plan" do
      plan = plan_fixture()
      {:ok, deleted} = Billing.delete_plan(plan)
      assert {:ok, %Plan{} = restored} = Billing.restore_plan(deleted)
      assert restored.deleted_at == nil
    end

    test "list_plans_including_deleted/1 returns soft-deleted plans" do
      plan = plan_fixture()
      org = Marquee.Repo.preload(plan, :organization).organization
      {:ok, _deleted} = Billing.delete_plan(plan)
      assert [found] = Billing.list_plans_including_deleted(org)
      assert found.id == plan.id
    end

    test "list_plans_including_deleted/1 scopes to org" do
      plan_a = plan_fixture()
      org_a = Marquee.Repo.preload(plan_a, :organization).organization
      _plan_b = plan_fixture()

      assert [found] = Billing.list_plans_including_deleted(org_a)
      assert found.id == plan_a.id
    end

    test "change_plan/1 returns a plan changeset" do
      plan = plan_fixture()
      assert %Ecto.Changeset{} = Billing.change_plan(plan)
    end
  end

  describe "list_active_plans/2" do
    import Marquee.BillingFixtures

    setup do
      %{org: insert(:organization)}
    end

    test "returns only active, non-deleted plans for the org", %{org: org} do
      active_plan = insert(:plan, organization: org, active: true)
      _inactive_plan = insert(:plan, organization: org, active: false)

      assert %{results: results} = Billing.list_active_plans(org)
      assert length(results) == 1
      assert hd(results).id == active_plan.id
    end

    test "excludes soft-deleted plans even if active", %{org: org} do
      plan = insert(:plan, organization: org, active: true)
      {:ok, _deleted} = Billing.delete_plan(plan)

      assert %{results: []} = Billing.list_active_plans(org)
    end

    test "does not return plans from a different org", %{org: org} do
      other_org = insert(:organization)
      _other_plan = insert(:plan, organization: other_org, active: true)
      own_plan = insert(:plan, organization: org, active: true)

      assert %{results: results} = Billing.list_active_plans(org)
      assert length(results) == 1
      assert hd(results).id == own_plan.id
    end

    test "returns empty results when no active plans exist", %{org: org} do
      _inactive = insert(:plan, organization: org, active: false)
      assert %{results: []} = Billing.list_active_plans(org)
    end
  end

  describe "subscriptions" do
    alias Marquee.Billing.Subscription

    import Marquee.BillingFixtures

    @invalid_attrs %{status: nil, stripe_subscription_id: nil, current_period_end: nil}

    setup do
      org = insert(:organization)
      user = insert(:user)
      plan = insert(:plan, organization: org)
      %{org: org, user: user, plan: plan}
    end

    test "list_subscriptions/2 returns subscriptions for the org" do
      subscription = subscription_fixture()
      org = Marquee.Repo.preload(subscription, :organization).organization
      assert %{results: [found]} = Billing.list_subscriptions(org)
      assert found.id == subscription.id
    end

    test "list_subscriptions/2 excludes other orgs" do
      sub_a = subscription_fixture()
      org_a = Marquee.Repo.preload(sub_a, :organization).organization
      _sub_b = subscription_fixture()

      assert %{results: [found]} = Billing.list_subscriptions(org_a)
      assert found.id == sub_a.id
    end

    test "get_subscription!/2 returns the subscription with given id" do
      subscription = subscription_fixture()
      org = Marquee.Repo.preload(subscription, :organization).organization
      assert Billing.get_subscription!(org, subscription.id).id == subscription.id
    end

    test "get_subscription!/2 raises for another org's subscription" do
      sub_a = subscription_fixture()
      org_b = insert(:organization)

      assert_raise Ecto.NoResultsError, fn ->
        Billing.get_subscription!(org_b, sub_a.id)
      end
    end

    test "create_subscription/1 with valid data creates a subscription", %{
      org: org,
      user: user,
      plan: plan
    } do
      valid_attrs = %{
        status: :active,
        stripe_subscription_id: "some stripe_subscription_id",
        current_period_end: ~U[2026-03-27 01:47:00Z],
        organization_id: org.id,
        user_id: user.id,
        plan_id: plan.id
      }

      assert {:ok, %Subscription{} = subscription} = Billing.create_subscription(valid_attrs)
      assert subscription.status == :active
      assert subscription.stripe_subscription_id == "some stripe_subscription_id"
      assert subscription.current_period_end == ~U[2026-03-27 01:47:00Z]
    end

    test "create_subscription/1 with invalid data returns error changeset" do
      assert {:error, :validation, %Ecto.Changeset{}} =
               Billing.create_subscription(@invalid_attrs)
    end

    test "update_subscription/2 with valid data updates the subscription" do
      subscription = subscription_fixture()

      update_attrs = %{
        status: :past_due,
        stripe_subscription_id: "some updated stripe_subscription_id",
        current_period_end: ~U[2026-03-28 01:47:00Z]
      }

      assert {:ok, %Subscription{} = subscription} =
               Billing.update_subscription(subscription, update_attrs)

      assert subscription.status == :past_due
      assert subscription.stripe_subscription_id == "some updated stripe_subscription_id"
      assert subscription.current_period_end == ~U[2026-03-28 01:47:00Z]
    end

    test "update_subscription/2 with invalid data returns error changeset" do
      subscription = subscription_fixture()
      org = Marquee.Repo.preload(subscription, :organization).organization

      assert {:error, :validation, %Ecto.Changeset{}} =
               Billing.update_subscription(subscription, @invalid_attrs)

      assert subscription.id == Billing.get_subscription!(org, subscription.id).id
    end

    test "delete_subscription/1 deletes the subscription" do
      subscription = subscription_fixture()
      org = Marquee.Repo.preload(subscription, :organization).organization
      assert {:ok, %Subscription{}} = Billing.delete_subscription(subscription)
      assert_raise Ecto.NoResultsError, fn -> Billing.get_subscription!(org, subscription.id) end
    end

    test "change_subscription/1 returns a subscription changeset" do
      subscription = subscription_fixture()
      assert %Ecto.Changeset{} = Billing.change_subscription(subscription)
    end
  end

  # ── Viewer subscriptions from Stripe ─────────────────────────────────────

  describe "create_subscription_from_stripe/3" do
    alias Marquee.Billing.ViewerSubscription

    setup do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "none")
      %{org: org, viewer: viewer}
    end

    test "creates a viewer subscription from Stripe data and broadcasts it", %{
      org: org,
      viewer: viewer
    } do
      plan = insert(:plan, organization: org)
      Phoenix.PubSub.subscribe(Marquee.PubSub, "events:#{org.id}")

      data = %{
        "id" => "sub_from_stripe_1",
        "customer" => "cus_from_stripe_1",
        "status" => "trialing",
        "cancel_at_period_end" => true,
        "current_period_start" => 1_700_000_000,
        "current_period_end" => 1_702_592_000,
        "trial_start" => 1_700_000_000,
        "trial_end" => 1_700_604_800,
        "items" => %{"data" => [%{"price" => %{"id" => plan.stripe_price_id}}]}
      }

      assert {:ok, %ViewerSubscription{} = sub} =
               Billing.create_subscription_from_stripe(org, viewer, data)

      assert sub.organization_id == org.id
      assert sub.viewer_id == viewer.id
      assert sub.plan_id == plan.id
      assert sub.stripe_subscription_id == "sub_from_stripe_1"
      assert sub.stripe_customer_id == "cus_from_stripe_1"
      assert sub.status == "trialing"
      assert sub.cancel_at_period_end == true
      assert sub.current_period_start == ~U[2023-11-14 22:13:20Z]
      assert sub.current_period_end == ~U[2023-12-14 22:13:20Z]
      assert sub.trial_end == ~U[2023-11-21 22:13:20Z]

      sub_id = sub.id

      assert_receive {:marquee_event,
                      {:viewer_subscription_created, %ViewerSubscription{id: ^sub_id}}, _}
    end

    test "leaves plan unset when the price matches no org plan", %{org: org, viewer: viewer} do
      data = %{
        "id" => "sub_from_stripe_no_plan",
        "customer" => "cus_x",
        "status" => "active",
        "items" => %{"data" => [%{"price" => %{"id" => "price_unknown"}}]}
      }

      assert {:ok, sub} = Billing.create_subscription_from_stripe(org, viewer, data)
      assert sub.plan_id == nil
      assert sub.cancel_at_period_end == false
    end

    test "returns a tagged validation error when required data is missing", %{
      org: org,
      viewer: viewer
    } do
      data = %{"id" => "sub_from_stripe_invalid", "customer" => "cus_x"}

      assert {:error, :validation, %Ecto.Changeset{} = changeset} =
               Billing.create_subscription_from_stripe(org, viewer, data)

      assert %{status: [_ | _]} = errors_on(changeset)

      refute Marquee.Repo.get_by(ViewerSubscription,
               stripe_subscription_id: "sub_from_stripe_invalid"
             )
    end
  end

  describe "mark_payment_succeeded/3" do
    alias Marquee.Billing.ViewerSubscription
    alias Marquee.Viewers.Viewer

    setup do
      org = insert(:organization)
      Phoenix.PubSub.subscribe(Marquee.PubSub, "events:#{org.id}")
      %{org: org}
    end

    defp insert_viewer_subscription(org, viewer, status) do
      %ViewerSubscription{}
      |> ViewerSubscription.changeset(%{
        organization_id: org.id,
        viewer_id: viewer.id,
        stripe_subscription_id: "sub_mps_#{System.unique_integer([:positive])}",
        stripe_customer_id: "cus_mps",
        status: status
      })
      |> Marquee.Repo.insert!()
    end

    test "activates an incomplete subscription and broadcasts :subscription_activated", %{
      org: org
    } do
      viewer = insert(:viewer, organization: org, subscription_status: "none")
      sub = insert_viewer_subscription(org, viewer, "incomplete")

      assert :ok = Billing.mark_payment_succeeded(org, viewer, sub)

      assert Marquee.Repo.get!(ViewerSubscription, sub.id).status == "active"
      assert Marquee.Repo.get!(Viewer, viewer.id).subscription_status == "active"
      viewer_id = viewer.id
      assert_receive {:marquee_event, {:subscription_activated, %Viewer{id: ^viewer_id}}, _}
      refute_received {:marquee_event, {:payment_recovered, _, _}, _}
    end

    test "recovers a past_due viewer and broadcasts :payment_recovered", %{org: org} do
      viewer = insert(:viewer, organization: org, subscription_status: "past_due")
      sub = insert_viewer_subscription(org, viewer, "past_due")

      assert :ok = Billing.mark_payment_succeeded(org, viewer, sub)

      assert Marquee.Repo.get!(ViewerSubscription, sub.id).status == "active"
      assert Marquee.Repo.get!(Viewer, viewer.id).subscription_status == "active"
      sub_id = sub.id

      assert_receive {:marquee_event,
                      {:payment_recovered, %Viewer{}, %ViewerSubscription{id: ^sub_id}}, _}

      refute_received {:marquee_event, {:subscription_activated, _}, _}
    end

    test "leaves other subscriptions unchanged without broadcasting", %{org: org} do
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      sub = insert_viewer_subscription(org, viewer, "active")

      assert :ok = Billing.mark_payment_succeeded(org, viewer, sub)

      assert Marquee.Repo.get!(ViewerSubscription, sub.id).status == "active"
      assert Marquee.Repo.get!(Viewer, viewer.id).subscription_status == "active"
      refute_received {:marquee_event, {:subscription_activated, _}, _}
      refute_received {:marquee_event, {:payment_recovered, _, _}, _}
    end
  end

  # ── PPV checkout ──────────────────────────────────────────────────────────

  describe "create_ppv_checkout/4" do
    setup :verify_on_exit!

    setup do
      org =
        insert(:organization,
          stripe_connect_account_id: "acct_test_123",
          stripe_connect_onboarding_complete: true
        )

      viewer = insert(:viewer, organization: org, email: "viewer@example.com")

      event =
        insert(:live_event,
          organization: org,
          access_type: "pay_per_view",
          ppv_price_cents: 999,
          title: "Big Stream"
        )

      %{org: org, viewer: viewer, event: event}
    end

    test "returns {:ok, url} on successful Stripe checkout creation", %{
      org: org,
      viewer: viewer,
      event: event
    } do
      expect(
        Marquee.Billing.MockStripeClient,
        :create_connected_payment_checkout_session,
        fn params ->
          assert params.organization_id == org.id
          assert params.viewer_id == viewer.id
          assert params.live_event_id == event.id
          assert params.viewer_email == viewer.email
          assert params.stripe_connect_account_id == org.stripe_connect_account_id
          assert [%{price_data: %{unit_amount: 999, currency: "usd"}}] = params.line_items
          {:ok, %{url: "https://checkout.stripe.com/pay/cs_test_abc"}}
        end
      )

      urls = %{
        success_url: "https://org.localhost/events/#{event.slug}/success",
        cancel_url: "https://org.localhost/events/#{event.slug}"
      }

      assert {:ok, "https://checkout.stripe.com/pay/cs_test_abc"} =
               Billing.create_ppv_checkout(event, viewer, org, urls)
    end

    test "returns {:error, :not_pay_per_view} for non-PPV event", %{
      org: org,
      viewer: viewer
    } do
      sub_event = insert(:live_event, organization: org, access_type: "subscribers_only")

      urls = %{
        success_url: "https://org.localhost/events/#{sub_event.slug}/success",
        cancel_url: "https://org.localhost/events/#{sub_event.slug}"
      }

      assert {:error, :not_pay_per_view} =
               Billing.create_ppv_checkout(sub_event, viewer, org, urls)
    end

    test "returns {:error, :stripe_not_connected} when org has no Stripe Connect", %{
      viewer: viewer,
      event: event
    } do
      disconnected_org = insert(:organization, stripe_connect_onboarding_complete: false)

      urls = %{
        success_url: "https://org.localhost/events/#{event.slug}/success",
        cancel_url: "https://org.localhost/events/#{event.slug}"
      }

      assert {:error, :stripe_not_connected} =
               Billing.create_ppv_checkout(event, viewer, disconnected_org, urls)
    end

    test "returns {:error, :stripe_error, details} when Stripe API fails", %{
      org: org,
      viewer: viewer,
      event: event
    } do
      expect(
        Marquee.Billing.MockStripeClient,
        :create_connected_payment_checkout_session,
        fn _params ->
          {:error, :stripe_error, %{message: "card_error"}}
        end
      )

      urls = %{
        success_url: "https://org.localhost/events/#{event.slug}/success",
        cancel_url: "https://org.localhost/events/#{event.slug}"
      }

      assert {:error, :stripe_error, _} = Billing.create_ppv_checkout(event, viewer, org, urls)
    end
  end
end
