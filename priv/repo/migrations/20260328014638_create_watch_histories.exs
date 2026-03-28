defmodule Bobine.Repo.Migrations.CreateWatchHistories do
  use Ecto.Migration

  def change do
    create table(:watch_histories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :watched_at, :utc_datetime, null: false
      add :organization_id, references(:organizations, on_delete: :delete_all, type: :binary_id), null: false
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :video_id, references(:videos, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:watch_histories, [:organization_id])
    create index(:watch_histories, [:user_id])
    create index(:watch_histories, [:video_id])
  end
end
