defmodule Bobine.Repo.Migrations.CreateCoupons do
  use Ecto.Migration

  def change do
    create table(:coupons, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all)

      add :stripe_coupon_id, :string
      add :stripe_promotion_code_id, :string
      add :code, :string, null: false
      add :name, :string
      add :percent_off, :decimal
      add :amount_off, :integer
      add :currency, :string
      add :duration, :string, null: false
      add :duration_in_months, :integer
      add :max_redemptions, :integer
      add :redeem_by, :utc_datetime
      add :active, :boolean, default: true, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:coupons, [:organization_id, :code])
    create index(:coupons, [:organization_id])
  end
end
