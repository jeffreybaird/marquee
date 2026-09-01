defmodule Marquee.Repo.Migrations.AddNewSeasonToSeries do
  use Ecto.Migration

  def change do
    alter table(:series) do
      add :new_season, :boolean, default: false, null: false
    end
  end
end
