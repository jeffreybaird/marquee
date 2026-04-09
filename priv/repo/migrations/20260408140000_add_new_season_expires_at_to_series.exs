defmodule Bobine.Repo.Migrations.AddNewSeasonExpiresAtToSeries do
  use Ecto.Migration

  def change do
    alter table(:series) do
      add :new_season_expires_at, :utc_datetime
    end
  end
end
