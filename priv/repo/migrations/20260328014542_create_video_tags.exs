defmodule Bobine.Repo.Migrations.CreateVideoTags do
  use Ecto.Migration

  def change do
    create table(:video_tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :video_id, references(:videos, on_delete: :delete_all, type: :binary_id), null: false
      add :tag_id, references(:tags, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:video_tags, [:video_id])
    create index(:video_tags, [:tag_id])
    create unique_index(:video_tags, [:video_id, :tag_id])
  end
end
