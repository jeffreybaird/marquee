defmodule Marquee.Repo.Migrations.AddCompositeIndexToProgresses do
  use Ecto.Migration

  def change do
    # Viewer progress lookups key by organization + viewer + video. A unique
    # index already exists on (viewer_id, video_id, organization_id), but
    # its column order does not serve queries like
    # `WHERE organization_id = ? AND viewer_id = ?` without scanning. This
    # index matches the hot-path shape.
    create index(:progresses, [:organization_id, :viewer_id, :video_id])
  end
end
