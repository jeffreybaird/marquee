defmodule Marquee.Repo.Migrations.AddAdminTourCompletedAtToMemberships do
  use Ecto.Migration

  def change do
    alter table(:memberships) do
      add :admin_tour_completed_at, :utc_datetime
    end
  end
end
