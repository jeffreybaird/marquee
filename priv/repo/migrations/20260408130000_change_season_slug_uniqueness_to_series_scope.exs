defmodule Marquee.Repo.Migrations.ChangeSeasonSlugUniquenessToSeriesScope do
  use Ecto.Migration

  def change do
    drop unique_index(:seasons, [:organization_id, :slug])
    create unique_index(:seasons, [:series_id, :slug])
  end
end
