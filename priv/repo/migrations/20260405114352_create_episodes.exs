defmodule Marquee.Repo.Migrations.CreateEpisodes do
  use Ecto.Migration

  def change do
    create table(:episodes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :nothing),
          null: false

      add :season_id,
          references(:seasons, type: :binary_id, on_delete: :nothing),
          null: false

      add :video_id,
          references(:videos, type: :binary_id, on_delete: :nothing),
          null: false

      add :episode_number, :integer, null: false
      add :title, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:episodes, [:season_id, :episode_number])
    create unique_index(:episodes, [:season_id, :video_id])
    create index(:episodes, [:organization_id])
    create index(:episodes, [:video_id])
  end
end
