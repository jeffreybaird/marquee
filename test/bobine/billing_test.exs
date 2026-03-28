defmodule Bobine.BillingTest do
  use Bobine.DataCase

  alias Bobine.Billing

  describe "plans" do
    alias Bobine.Billing.Plan

    import Bobine.BillingFixtures

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

    test "list_plans/0 returns all plans" do
      plan = plan_fixture()
      assert Billing.list_plans() == [plan]
    end

    test "get_plan!/1 returns the plan with given id" do
      plan = plan_fixture()
      assert Billing.get_plan!(plan.id) == plan
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
      assert {:error, %Ecto.Changeset{}} = Billing.create_plan(@invalid_attrs)
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
      assert {:error, %Ecto.Changeset{}} = Billing.update_plan(plan, @invalid_attrs)
      assert plan == Billing.get_plan!(plan.id)
    end

    test "delete_plan/1 deletes the plan" do
      plan = plan_fixture()
      assert {:ok, %Plan{}} = Billing.delete_plan(plan)
      assert_raise Ecto.NoResultsError, fn -> Billing.get_plan!(plan.id) end
    end

    test "change_plan/1 returns a plan changeset" do
      plan = plan_fixture()
      assert %Ecto.Changeset{} = Billing.change_plan(plan)
    end
  end

  describe "subscriptions" do
    alias Bobine.Billing.Subscription

    import Bobine.BillingFixtures

    @invalid_attrs %{status: nil, stripe_subscription_id: nil, current_period_end: nil}

    setup do
      org = insert(:organization)
      user = insert(:user)
      plan = insert(:plan, organization: org)
      %{org: org, user: user, plan: plan}
    end

    test "list_subscriptions/0 returns all subscriptions" do
      subscription = subscription_fixture()
      assert Billing.list_subscriptions() == [subscription]
    end

    test "get_subscription!/1 returns the subscription with given id" do
      subscription = subscription_fixture()
      assert Billing.get_subscription!(subscription.id) == subscription
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
      assert {:error, %Ecto.Changeset{}} = Billing.create_subscription(@invalid_attrs)
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

      assert {:error, %Ecto.Changeset{}} =
               Billing.update_subscription(subscription, @invalid_attrs)

      assert subscription == Billing.get_subscription!(subscription.id)
    end

    test "delete_subscription/1 deletes the subscription" do
      subscription = subscription_fixture()
      assert {:ok, %Subscription{}} = Billing.delete_subscription(subscription)
      assert_raise Ecto.NoResultsError, fn -> Billing.get_subscription!(subscription.id) end
    end

    test "change_subscription/1 returns a subscription changeset" do
      subscription = subscription_fixture()
      assert %Ecto.Changeset{} = Billing.change_subscription(subscription)
    end
  end
end
