defmodule Bobine.Billing.PlatformSubscriptionTest do
  use Bobine.DataCase, async: true

  alias Bobine.Billing.PlatformSubscription

  describe "changeset/2" do
    test "valid changeset with required attrs" do
      org = insert(:organization)
      plan = insert(:platform_plan)

      attrs = %{
        organization_id: org.id,
        platform_plan_id: plan.id,
        stripe_subscription_id: "sub_test",
        status: :active
      }

      changeset = PlatformSubscription.changeset(%PlatformSubscription{}, attrs)
      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = PlatformSubscription.changeset(%PlatformSubscription{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:organization_id]
      assert errors[:platform_plan_id]
      assert errors[:stripe_subscription_id]
      assert errors[:status]
    end

    test "enforces unique constraint on organization_id" do
      org = insert(:organization)
      plan = insert(:platform_plan)
      insert(:platform_subscription, organization: org, platform_plan: plan)

      plan2 =
        insert(:platform_plan,
          slug: "other",
          usage_tier: :super,
          business_tier: :small_business
        )

      {:error, changeset} =
        %PlatformSubscription{}
        |> PlatformSubscription.changeset(%{
          organization_id: org.id,
          platform_plan_id: plan2.id,
          stripe_subscription_id: "sub_dup",
          status: :active
        })
        |> Repo.insert()

      assert errors_on(changeset)[:organization_id]
    end
  end
end
