defmodule Bobine.Billing.Plan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "plans" do
    field :name, :string
    field :stripe_price_id, :string
    field :stripe_product_id, :string
    field :amount, :integer
    field :interval, Ecto.Enum, values: [:monthly, :yearly]
    field :active, :boolean, default: false

    belongs_to :organization, Bobine.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :name,
      :stripe_price_id,
      :stripe_product_id,
      :amount,
      :interval,
      :active,
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
  end
end
