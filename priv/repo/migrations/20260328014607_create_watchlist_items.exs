defmodule Bobine.Repo.Migrations.CreateWatchlistItems do
  use Ecto.Migration

  def change do
    create table(:watchlist_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :integer
      add :auto_remove_on_watch, :boolean, default: false, null: false

      add :organization_id, references(:organizations, on_delete: :delete_all, type: :binary_id),
        null: false

      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :video_id, references(:videos, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:watchlist_items, [:organization_id])
    create index(:watchlist_items, [:user_id])
    create index(:watchlist_items, [:video_id])
    create unique_index(:watchlist_items, [:user_id, :video_id, :organization_id])
  end
end
