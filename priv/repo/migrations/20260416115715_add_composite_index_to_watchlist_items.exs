defmodule Bobine.Repo.Migrations.AddCompositeIndexToWatchlistItems do
  use Ecto.Migration

  def change do
    # Supports list queries scoped by organization + user for the operator
    # "who has what on their list" views. Existing indexes cover
    # (user_id, video_id, organization_id) for uniqueness and each column
    # individually, but none starts with (organization_id, user_id) — the
    # shape Postgres needs for `WHERE organization_id = ? AND user_id = ?`
    # hot-path lookups to use an index rather than a sequential scan.
    create index(:watchlist_items, [:organization_id, :user_id])
  end
end
