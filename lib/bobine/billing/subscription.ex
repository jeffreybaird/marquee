defmodule Bobine.Billing.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "subscriptions" do
    field :stripe_subscription_id, :string
    field :status, Ecto.Enum, values: [:active, :past_due, :canceled, :trialing]
    field :current_period_end, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :user, Bobine.Accounts.User
    belongs_to :plan, Bobine.Billing.Plan

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:stripe_subscription_id, :status, :current_period_end, :organization_id, :user_id, :plan_id])
    |> validate_required([:stripe_subscription_id, :status, :current_period_end, :organization_id, :user_id, :plan_id])
  end
end
