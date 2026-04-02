defmodule Bobine.Billing.PlatformSubscription do
  @moduledoc """
  Tracks an organization's subscription to a Bobine platform plan.

  Each org can have at most one active platform subscription. This is
  enforced by a unique constraint on `organization_id`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "platform_subscriptions" do
    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :platform_plan, Bobine.Billing.PlatformPlan

    field :stripe_subscription_id, :string
    field :stripe_customer_id, :string
    field :status, Ecto.Enum, values: [:active, :past_due, :canceled, :trialing, :unpaid]
    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime
    field :trial_start, :utc_datetime
    field :trial_end, :utc_datetime
    field :canceled_at, :utc_datetime
    field :cancel_at_period_end, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @required_fields [:organization_id, :platform_plan_id, :stripe_subscription_id, :status]
  @optional_fields [
    :stripe_customer_id,
    :current_period_start,
    :current_period_end,
    :trial_start,
    :trial_end,
    :canceled_at,
    :cancel_at_period_end
  ]

  @doc false
  def changeset(platform_subscription, attrs) do
    platform_subscription
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:organization_id])
    |> unique_constraint(:stripe_subscription_id)
  end
end
