defmodule Bobine.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stripe_subscription_id, :string, null: false
      add :status, :string, null: false
      add :current_period_end, :utc_datetime, null: false

      add :organization_id, references(:organizations, on_delete: :delete_all, type: :binary_id),
        null: false

      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :plan_id, references(:plans, on_delete: :nilify_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:subscriptions, [:organization_id])
    create index(:subscriptions, [:user_id])
    create index(:subscriptions, [:plan_id])
  end
end
