defmodule Marquee.Repo.Migrations.ContentManagementFeature do
  use Ecto.Migration

  def change do
    # --- Collections: add missing fields and unique index ---
    alter table(:collections) do
      add :cover_image_url, :string
      add :visible, :boolean, default: true, null: false
    end

    create unique_index(:collections, [:organization_id, :slug])

    # --- CollectionItem join table ---
    create table(:collection_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :integer, default: 0, null: false

      add :organization_id,
          references(:organizations, on_delete: :delete_all, type: :binary_id),
          null: false

      add :collection_id,
          references(:collections, on_delete: :delete_all, type: :binary_id),
          null: false

      add :video_id,
          references(:videos, on_delete: :delete_all, type: :binary_id),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:collection_items, [:organization_id])
    create unique_index(:collection_items, [:collection_id, :video_id])

    # --- VideoTags: add organization_id ---
    alter table(:video_tags) do
      add :organization_id,
          references(:organizations, on_delete: :delete_all, type: :binary_id)
    end

    create index(:video_tags, [:organization_id])

    # --- RowItems: add organization_id ---
    alter table(:row_items) do
      add :organization_id,
          references(:organizations, on_delete: :delete_all, type: :binary_id)
    end

    create index(:row_items, [:organization_id])

    # --- Rows: add source_id and max_items ---
    alter table(:rows) do
      add :source_id, :binary_id
      add :max_items, :integer, default: 20
    end
  end
end
