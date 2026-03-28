defmodule Bobine.BillingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Bobine.Billing` context.
  """

  @doc """
  Generate a plan.
  """
  def plan_fixture(attrs \\ %{}) do
    {:ok, plan} =
      attrs
      |> Enum.into(%{
        active: true,
        amount: 42,
        interval: :monthly,
        name: "some name",
        stripe_price_id: "some stripe_price_id",
        stripe_product_id: "some stripe_product_id"
      })
      |> Bobine.Billing.create_plan()

    plan
  end

  @doc """
  Generate a subscription.
  """
  def subscription_fixture(attrs \\ %{}) do
    {:ok, subscription} =
      attrs
      |> Enum.into(%{
        current_period_end: ~U[2026-03-27 01:47:00Z],
        status: :active,
        stripe_subscription_id: "some stripe_subscription_id"
      })
      |> Bobine.Billing.create_subscription()

    subscription
  end
end
