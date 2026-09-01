defmodule Marquee.Repo.Migrations.AddPolymorphicRefsToWatchlistItems do
  use Ecto.Migration

  def change do
    alter table(:watchlist_items) do
      add :season_id, references(:seasons, type: :binary_id, on_delete: :nothing)
      add :series_id, references(:series, type: :binary_id, on_delete: :nothing)
      add :item_type, :string, default: "video", null: false

      modify :video_id, references(:videos, on_delete: :delete_all, type: :binary_id),
        null: true,
        from: {references(:videos, on_delete: :delete_all, type: :binary_id), null: false}
    end

    # Backfill any existing rows that pre-date the column.
    execute(
      "UPDATE watchlist_items SET item_type = 'video' WHERE item_type IS NULL",
      ""
    )

    # The legacy unique index on (viewer_id, video_id, organization_id) is
    # still correct for video rows. Add separate viewer-scoped uniqueness for
    # the new polymorphic columns so we don't queue the same season/series
    # twice in one watchlist.
    create unique_index(:watchlist_items, [:viewer_id, :season_id, :organization_id],
             where: "season_id IS NOT NULL AND deleted_at IS NULL",
             name: :watchlist_items_viewer_season_org_unique
           )

    create unique_index(:watchlist_items, [:viewer_id, :series_id, :organization_id],
             where: "series_id IS NOT NULL AND deleted_at IS NULL",
             name: :watchlist_items_viewer_series_org_unique
           )

    create index(:watchlist_items, [:season_id])
    create index(:watchlist_items, [:series_id])
  end
end
