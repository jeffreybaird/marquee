defmodule Marquee.Repo.Migrations.AddCustomThumbnailUrlToVideos do
  use Ecto.Migration

  def change do
    alter table(:videos) do
      add :custom_thumbnail_url, :string
    end
  end
end
