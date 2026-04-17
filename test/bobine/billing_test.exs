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

    test "list_plans/2 returns plans for the given org" do
      plan = plan_fixture()
      org = Bobine.Repo.preload(plan, :organization).organization
      assert %{results: [^plan]} = Billing.list_plans(org)
    end

    test "get_plan!/2 returns the plan with given id" do
      plan = plan_fixture()
      org = Bobine.Repo.preload(plan, :organization).organization
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
      org = Bobine.Repo.preload(plan, :organization).organization
      assert {:error, :validation, %Ecto.Changeset{}} = Billing.update_plan(plan, @invalid_attrs)
      assert plan.id == Billing.get_plan!(org, plan.id).id
    end

    test "delete_plan/1 soft-deletes the plan" do
      plan = plan_fixture()
      org = Bobine.Repo.preload(plan, :organization).organization
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
      org = Bobine.Repo.preload(plan, :organization).organization
      {:ok, _deleted} = Billing.delete_plan(plan)
      assert [found] = Billing.list_plans_including_deleted(org)
      assert found.id == plan.id
    end

    test "list_plans_including_deleted/1 scopes to org" do
      plan_a = plan_fixture()
      org_a = Bobine.Repo.preload(plan_a, :organization).organization
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
    import Bobine.BillingFixtures

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
    alias Bobine.Billing.Subscription

    import Bobine.BillingFixtures

    @invalid_attrs %{status: nil, stripe_subscription_id: nil, current_period_end: nil}

    setup do
      org = insert(:organization)
      user = insert(:user)
      plan = insert(:plan, organization: org)
      %{org: org, user: user, plan: plan}
    end

    test "list_subscriptions/2 returns subscriptions for the org" do
      subscription = subscription_fixture()
      org = Bobine.Repo.preload(subscription, :organization).organization
      assert %{results: [found]} = Billing.list_subscriptions(org)
      assert found.id == subscription.id
    end

    test "list_subscriptions/2 excludes other orgs" do
      sub_a = subscription_fixture()
      org_a = Bobine.Repo.preload(sub_a, :organization).organization
      _sub_b = subscription_fixture()

      assert %{results: [found]} = Billing.list_subscriptions(org_a)
      assert found.id == sub_a.id
    end

    test "get_subscription!/2 returns the subscription with given id" do
      subscription = subscription_fixture()
      org = Bobine.Repo.preload(subscription, :organization).organization
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
      org = Bobine.Repo.preload(subscription, :organization).organization

      assert {:error, :validation, %Ecto.Changeset{}} =
               Billing.update_subscription(subscription, @invalid_attrs)

      assert subscription.id == Billing.get_subscription!(org, subscription.id).id
    end

    test "delete_subscription/1 deletes the subscription" do
      subscription = subscription_fixture()
      org = Bobine.Repo.preload(subscription, :organization).organization
      assert {:ok, %Subscription{}} = Billing.delete_subscription(subscription)
      assert_raise Ecto.NoResultsError, fn -> Billing.get_subscription!(org, subscription.id) end
    end

    test "change_subscription/1 returns a subscription changeset" do
      subscription = subscription_fixture()
      assert %Ecto.Changeset{} = Billing.change_subscription(subscription)
    end
  end
end
