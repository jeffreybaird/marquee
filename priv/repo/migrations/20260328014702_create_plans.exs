defmodule Bobine.Repo.Migrations.CreatePlans do
  use Ecto.Migration

  def change do
    create table(:plans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :stripe_price_id, :string, null: false
      add :stripe_product_id, :string, null: false
      add :amount, :integer, null: false
      add :interval, :string, null: false
      add :active, :boolean, default: false, null: false
      add :organization_id, references(:organizations, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:plans, [:organization_id])
  end
end
