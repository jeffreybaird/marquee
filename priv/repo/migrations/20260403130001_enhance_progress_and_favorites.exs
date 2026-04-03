defmodule Bobine.Repo.Migrations.EnhanceProgressAndFavorites do
  use Ecto.Migration

  def change do
    # Add duration field to progresses
    alter table(:progresses) do
      add :duration, :float
    end

    # Add viewer-scoped unique index for progresses
    create unique_index(:progresses, [:viewer_id, :video_id, :organization_id],
      where: "viewer_id IS NOT NULL"
    )

    # Add viewer-scoped unique index for favorites
    create unique_index(:favorites, [:viewer_id, :video_id, :organization_id],
      where: "viewer_id IS NOT NULL"
    )

    # Add index on watch_histories for viewer + last watched queries
    create index(:watch_histories, [:organization_id, :viewer_id, :watched_at])
  end
end
