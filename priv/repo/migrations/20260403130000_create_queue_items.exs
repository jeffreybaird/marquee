defmodule Bobine.Repo.Migrations.CreateQueueItems do
  use Ecto.Migration

  def change do
    create table(:queue_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :integer, null: false
      add :added_from, :string
      add :added_at, :utc_datetime, null: false, default: fragment("now()")

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :viewer_id, references(:viewers, type: :binary_id, on_delete: :delete_all), null: false
      add :video_id, references(:videos, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:queue_items, [:organization_id, :viewer_id])
    create unique_index(:queue_items, [:organization_id, :viewer_id, :video_id])
    create index(:queue_items, [:organization_id, :viewer_id, :position])
  end
end
