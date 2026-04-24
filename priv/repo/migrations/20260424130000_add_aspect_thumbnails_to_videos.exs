defmodule Bobine.Repo.Migrations.AddAspectThumbnailsToVideos do
  use Ecto.Migration

  def change do
    alter table(:videos) do
      add :portrait_thumbnail_url, :string
      add :landscape_thumbnail_url, :string
    end

    # Historical `custom_thumbnail_url` values were functionally landscape —
    # that's what Mux emits by default and what every existing card
    # renders against. Backfill so nothing visually regresses on deploy.
    execute(
      "UPDATE videos SET landscape_thumbnail_url = custom_thumbnail_url WHERE custom_thumbnail_url IS NOT NULL",
      "UPDATE videos SET landscape_thumbnail_url = NULL"
    )
  end
end
