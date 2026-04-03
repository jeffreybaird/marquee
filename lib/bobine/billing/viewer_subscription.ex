defmodule Bobine.Billing.ViewerSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "viewer_subscriptions" do
    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :viewer, Bobine.Viewers.Viewer
    belongs_to :plan, Bobine.Billing.Plan

    field :stripe_subscription_id, :string
    field :stripe_customer_id, :string
    field :status, :string
    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime
    field :trial_start, :utc_datetime
    field :trial_end, :utc_datetime
    field :canceled_at, :utc_datetime
    field :cancel_at_period_end, :boolean, default: false
    field :application_fee_percent, :decimal, default: Decimal.new("2.0")
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :organization_id,
      :viewer_id,
      :plan_id,
      :stripe_subscription_id,
      :stripe_customer_id,
      :status,
      :current_period_start,
      :current_period_end,
      :trial_start,
      :trial_end,
      :canceled_at,
      :cancel_at_period_end,
      :application_fee_percent
    ])
    |> validate_required([:organization_id, :viewer_id, :stripe_subscription_id, :status])
    |> unique_constraint(:stripe_subscription_id)
  end
end
