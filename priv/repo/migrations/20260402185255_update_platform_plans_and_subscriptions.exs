defmodule Marquee.Repo.Migrations.UpdatePlatformPlansAndSubscriptions do
  use Ecto.Migration

  def change do
    # ── PlatformPlan additions ──────────────────────────────────────────
    alter table(:platform_plans) do
      add :slug, :string
      add :currency, :string, default: "usd"
      add :usage_tier, :string
      add :business_tier, :string
      add :max_monthly_views, :integer
      add :max_storage_gb, :integer
      add :max_webhook_endpoints, :integer
      add :enabled_features, {:array, :string}, default: []
      add :description, :string
      add :highlight, :boolean, default: false
      add :position, :integer, default: 0
      add :deleted_at, :utc_datetime
    end

    # Rename max_team_members to max_team_seats for consistency with spec
    rename table(:platform_plans), :max_team_members, to: :max_team_seats

    create unique_index(:platform_plans, [:slug])
    create unique_index(:platform_plans, [:usage_tier, :business_tier])
    create index(:platform_plans, [:active])

    # ── PlatformSubscription additions ──────────────────────────────────
    alter table(:platform_subscriptions) do
      add :current_period_start, :utc_datetime
      add :trial_start, :utc_datetime
      add :trial_end, :utc_datetime
      add :canceled_at, :utc_datetime
      add :cancel_at_period_end, :boolean, default: false
    end

    # Upgrade existing non-unique index to unique
    drop index(:platform_subscriptions, [:stripe_subscription_id])
    create unique_index(:platform_subscriptions, [:stripe_subscription_id])
  end
end
