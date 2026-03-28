defmodule Bobine.Billing.PlatformSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "platform_subscriptions" do
    field :stripe_subscription_id, :string
    field :stripe_customer_id, :string
    field :status, Ecto.Enum, values: [:active, :past_due, :canceled, :trialing]
    field :current_period_end, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :platform_plan, Bobine.Billing.PlatformPlan

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(platform_subscription, attrs) do
    platform_subscription
    |> cast(attrs, [
      :stripe_subscription_id,
      :stripe_customer_id,
      :status,
      :current_period_end,
      :organization_id,
      :platform_plan_id
    ])
    |> validate_required([:organization_id, :platform_plan_id, :stripe_subscription_id, :status])
    |> unique_constraint([:organization_id])
  end
end
