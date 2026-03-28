defmodule Bobine.Repo.Migrations.CreatePlatformSubscriptions do
  use Ecto.Migration

  def change do
    create table(:platform_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stripe_subscription_id, :string, null: false
      add :stripe_customer_id, :string
      add :status, :string, null: false
      add :current_period_end, :utc_datetime

      add :organization_id, references(:organizations, on_delete: :delete_all, type: :binary_id),
        null: false

      add :platform_plan_id,
          references(:platform_plans, on_delete: :delete_all, type: :binary_id),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:platform_subscriptions, [:organization_id])
    create index(:platform_subscriptions, [:platform_plan_id])
    create index(:platform_subscriptions, [:stripe_subscription_id])
  end
end
