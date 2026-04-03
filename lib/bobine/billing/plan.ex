defmodule Bobine.Billing.Plan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "plans" do
    field :name, :string
    field :description, :string
    field :stripe_price_id, :string
    field :stripe_product_id, :string
    field :amount, :integer
    field :currency, :string, default: "usd"
    field :interval, Ecto.Enum, values: [:monthly, :yearly]
    field :trial_period_days, :integer
    field :active, :boolean, default: false
    field :position, :integer, default: 0
    field :features, {:array, :string}, default: []
    field :deleted_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :name,
      :description,
      :stripe_price_id,
      :stripe_product_id,
      :amount,
      :currency,
      :interval,
      :trial_period_days,
      :active,
      :position,
      :features,
      :organization_id
    ])
    |> validate_required([
      :name,
      :stripe_price_id,
      :stripe_product_id,
      :amount,
      :interval,
      :organization_id
    ])
    |> validate_number(:amount, greater_than_or_equal_to: 0)
    |> validate_number(:trial_period_days, greater_than_or_equal_to: 0)
  end
end
