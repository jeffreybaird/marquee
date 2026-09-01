defmodule Marquee.Billing.PlatformSubscriptionTest do
  use Marquee.DataCase, async: true

  alias Marquee.Billing.PlatformSubscription

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
      assert errors[:status]
    end

    # platform_plan_id and stripe_subscription_id are intentionally optional so a
    # trialing subscription can be created at signup with no Stripe subscription
    # and no plan row (trial limits come from PlatformBilling.trial_plan/0).
    test "valid trial changeset without plan or stripe subscription" do
      org = insert(:organization)

      attrs = %{
        organization_id: org.id,
        status: :trialing,
        trial_start: DateTime.utc_now() |> DateTime.truncate(:second),
        trial_end: DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
      }

      changeset = PlatformSubscription.changeset(%PlatformSubscription{}, attrs)

      assert changeset.valid?
      refute errors_on(changeset)[:platform_plan_id]
      refute errors_on(changeset)[:stripe_subscription_id]
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
