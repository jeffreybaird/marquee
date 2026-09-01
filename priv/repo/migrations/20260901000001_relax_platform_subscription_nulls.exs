defmodule Marquee.Repo.Migrations.RelaxPlatformSubscriptionNulls do
  use Ecto.Migration

  # A trialing subscription is created at signup with no Stripe subscription
  # (payment deferred to day 30) and no platform plan row (trial limits come
  # from PlatformBilling.trial_plan/0, mirroring default_free_plan/0). Both
  # columns must therefore allow NULL.
  def up do
    alter table(:platform_subscriptions) do
      modify :stripe_subscription_id, :string, null: true

      modify :platform_plan_id,
             references(:platform_plans, on_delete: :delete_all, type: :binary_id),
             null: true,
             from: references(:platform_plans, on_delete: :delete_all, type: :binary_id)
    end
  end

  def down do
    alter table(:platform_subscriptions) do
      modify :stripe_subscription_id, :string, null: false

      modify :platform_plan_id,
             references(:platform_plans, on_delete: :delete_all, type: :binary_id),
             null: false,
             from: references(:platform_plans, on_delete: :delete_all, type: :binary_id)
    end
  end
end
