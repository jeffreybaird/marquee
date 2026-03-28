defmodule Bobine.Repo.Migrations.CreateAnalyticsEvents do
  use Ecto.Migration

  def change do
    create table(:analytics_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :metadata, :map
      add :occurred_at, :utc_datetime, null: false

      add :organization_id, references(:organizations, on_delete: :delete_all, type: :binary_id),
        null: false

      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id)
      add :video_id, references(:videos, on_delete: :delete_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:analytics_events, [:organization_id])
    create index(:analytics_events, [:user_id])
    create index(:analytics_events, [:video_id])
  end
end
