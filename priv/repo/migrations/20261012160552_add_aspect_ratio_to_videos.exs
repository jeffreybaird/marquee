defmodule Marquee.Repo.Migrations.AddAspectRatioToVideos do
  use Ecto.Migration

  def change do
    alter table(:videos) do
      # Mux-reported "W:H" ratio (e.g. "9:16"); nil until known.
      add :aspect_ratio, :string
    end
  end
end
