defmodule Marquee.Repo.Migrations.AddOnboardingCompletedAtToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :onboarding_completed_at, :utc_datetime
    end
  end
end
