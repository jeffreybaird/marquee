defmodule Bobine.Repo.Migrations.FixUserIdNotNullOnEngagementTables do
  use Ecto.Migration

  def change do
    # The earlier migration (20260403130002) was recorded as run but did not
    # actually drop the NOT NULL constraint on user_id. This migration
    # applies the change so viewer-only engagement records can be created
    # without an associated operator user.

    alter table(:favorites) do
      modify :user_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    alter table(:watchlist_items) do
      modify :user_id, :binary_id, null: true, from: {:binary_id, null: false}
    end
  end
end
