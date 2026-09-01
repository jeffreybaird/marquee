defmodule Marquee.Repo.Migrations.AddFeaturesToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :features, :map, default: %{}
    end
  end
end
