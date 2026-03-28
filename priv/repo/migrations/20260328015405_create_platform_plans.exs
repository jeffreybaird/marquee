defmodule Bobine.Repo.Migrations.CreatePlatformPlans do
  use Ecto.Migration

  def change do
    create table(:platform_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :stripe_price_id, :string
      add :stripe_product_id, :string
      add :amount, :integer, null: false
      add :interval, :string, null: false
      add :features, :map
      add :max_videos, :integer
      add :max_team_members, :integer
      add :transaction_fee_percent, :float, null: false, default: 5.0
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:platform_plans, [:stripe_price_id])
  end
end
