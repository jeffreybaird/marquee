defmodule Marquee.Repo.Migrations.MakeUserIdNullableForViewerEngagement do
  use Ecto.Migration

  def change do
    # Make user_id nullable on engagement tables so viewer-only records can be created.
    # Previously these tables required user_id (operator identity). Now viewers
    # (customer identity) can also create progress, watch history, etc. without
    # needing an associated operator user.

    alter table(:progresses) do
      modify :user_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    alter table(:watch_histories) do
      modify :user_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    alter table(:favorites) do
      modify :user_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    alter table(:watchlist_items) do
      modify :user_id, :binary_id, null: true, from: {:binary_id, null: false}
    end
  end
end
