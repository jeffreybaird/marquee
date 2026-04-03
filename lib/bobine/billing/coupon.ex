defmodule Bobine.Billing.Coupon do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "coupons" do
    belongs_to :organization, Bobine.Accounts.Organization

    field :stripe_coupon_id, :string
    field :stripe_promotion_code_id, :string
    field :code, :string
    field :name, :string
    field :percent_off, :decimal
    field :amount_off, :integer
    field :currency, :string
    field :duration, Ecto.Enum, values: [:once, :repeating, :forever]
    field :duration_in_months, :integer
    field :max_redemptions, :integer
    field :redeem_by, :utc_datetime
    field :active, :boolean, default: true
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(coupon, attrs) do
    coupon
    |> cast(attrs, [
      :organization_id,
      :stripe_coupon_id,
      :stripe_promotion_code_id,
      :code,
      :name,
      :percent_off,
      :amount_off,
      :currency,
      :duration,
      :duration_in_months,
      :max_redemptions,
      :redeem_by,
      :active
    ])
    |> validate_required([:organization_id, :code, :duration])
    |> update_change(:code, &String.upcase/1)
    |> validate_discount_type()
    |> validate_duration_months()
    |> unique_constraint([:organization_id, :code])
  end

  defp validate_discount_type(changeset) do
    percent = get_field(changeset, :percent_off)
    amount = get_field(changeset, :amount_off)

    cond do
      percent && amount ->
        add_error(changeset, :percent_off, "cannot set both percent_off and amount_off")

      is_nil(percent) && is_nil(amount) ->
        add_error(changeset, :percent_off, "must set either percent_off or amount_off")

      true ->
        changeset
    end
  end

  defp validate_duration_months(changeset) do
    if get_field(changeset, :duration) == :repeating &&
         is_nil(get_field(changeset, :duration_in_months)) do
      add_error(changeset, :duration_in_months, "required when duration is repeating")
    else
      changeset
    end
  end
end
