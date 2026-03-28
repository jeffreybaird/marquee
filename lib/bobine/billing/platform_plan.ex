defmodule Bobine.Billing.PlatformPlan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "platform_plans" do
    field :name, :string
    field :stripe_price_id, :string
    field :stripe_product_id, :string
    field :amount, :integer
    field :interval, Ecto.Enum, values: [:monthly, :yearly]
    field :features, :map
    field :max_videos, :integer
    field :max_team_members, :integer
    field :transaction_fee_percent, :float, default: 5.0
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(platform_plan, attrs) do
    platform_plan
    |> cast(attrs, [
      :name,
      :stripe_price_id,
      :stripe_product_id,
      :amount,
      :interval,
      :features,
      :max_videos,
      :max_team_members,
      :transaction_fee_percent,
      :active
    ])
    |> validate_required([:name, :amount, :interval, :transaction_fee_percent])
  end
end
