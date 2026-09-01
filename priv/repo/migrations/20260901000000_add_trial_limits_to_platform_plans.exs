defmodule Marquee.Repo.Migrations.AddTrialLimitsToPlatformPlans do
  use Ecto.Migration

  def change do
    alter table(:platform_plans) do
      # Total video duration a plan permits, in seconds (nil = unlimited).
      add :max_total_duration_seconds, :integer
      # Maximum number of end-user viewers a plan permits (nil = unlimited).
      add :max_viewers, :integer
      # Whether the plan permits configuring a custom domain.
      add :allow_custom_domain, :boolean, default: false, null: false
    end
  end
end
