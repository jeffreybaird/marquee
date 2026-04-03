defmodule Bobine.Repo.Migrations.CreateViewerSubscriptionsAndAddStripeCustomerId do
  use Ecto.Migration

  def change do
    create table(:viewer_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :viewer_id, references(:viewers, type: :binary_id, on_delete: :delete_all), null: false
      add :plan_id, references(:plans, type: :binary_id, on_delete: :nilify_all)

      add :stripe_subscription_id, :string, null: false
      add :stripe_customer_id, :string
      add :status, :string, null: false
      add :current_period_start, :utc_datetime
      add :current_period_end, :utc_datetime
      add :trial_start, :utc_datetime
      add :trial_end, :utc_datetime
      add :canceled_at, :utc_datetime
      add :cancel_at_period_end, :boolean, default: false, null: false
      add :application_fee_percent, :decimal, default: 2.0, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:viewer_subscriptions, [:stripe_subscription_id])
    create index(:viewer_subscriptions, [:organization_id, :viewer_id])
    create index(:viewer_subscriptions, [:organization_id])
    create index(:viewer_subscriptions, [:status])

    alter table(:viewers) do
      add :stripe_customer_id, :string
    end

    create index(:viewers, [:organization_id, :stripe_customer_id])
  end
end
