defmodule Marquee.BillingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Marquee.Billing` context.
  """

  import Marquee.Factory

  @doc """
  Generate a plan.
  """
  def plan_fixture(attrs \\ %{}) do
    org = insert(:organization)

    {:ok, plan} =
      attrs
      |> Enum.into(%{
        active: true,
        amount: 42,
        interval: :monthly,
        name: "some name",
        stripe_price_id: "some stripe_price_id",
        stripe_product_id: "some stripe_product_id",
        organization_id: org.id
      })
      |> Marquee.Billing.create_plan()

    plan
  end

  @doc """
  Generate a subscription.
  """
  def subscription_fixture(attrs \\ %{}) do
    org = insert(:organization)
    user = insert(:user)
    plan = plan_fixture(%{organization_id: org.id})

    {:ok, subscription} =
      attrs
      |> Enum.into(%{
        current_period_end: ~U[2026-03-27 01:47:00Z],
        status: :active,
        stripe_subscription_id: "some stripe_subscription_id",
        organization_id: org.id,
        user_id: user.id,
        plan_id: plan.id
      })
      |> Marquee.Billing.create_subscription()

    subscription
  end
end
