defmodule Bobine.Repo.Migrations.CreateSeasons do
  use Ecto.Migration

  def change do
    create table(:seasons, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :nothing),
          null: false

      add :series_id,
          references(:series, type: :binary_id, on_delete: :nothing),
          null: false

      add :title, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :cover_image_url, :string
      add :season_number, :integer, null: false
      add :episode_count, :integer, default: 0, null: false
      add :visible, :boolean, default: true, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:seasons, [:series_id, :season_number])
    create unique_index(:seasons, [:organization_id, :slug])
    create index(:seasons, [:organization_id])
    create index(:seasons, [:series_id])
  end
end
