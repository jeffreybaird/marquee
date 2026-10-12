defmodule Marquee.Repo.Migrations.CreateShortFeedItems do
  use Ecto.Migration

  def change do
    create table(:short_feed_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, on_delete: :delete_all, type: :binary_id),
          null: false

      add :video_id,
          references(:videos, on_delete: :delete_all, type: :binary_id),
          null: false

      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:short_feed_items, [:organization_id, :video_id])
    create index(:short_feed_items, [:organization_id, :position])
    create index(:short_feed_items, [:video_id])
  end
end
