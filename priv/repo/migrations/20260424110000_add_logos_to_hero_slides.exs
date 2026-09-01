defmodule Marquee.Repo.Migrations.AddLogosToHeroSlides do
  use Ecto.Migration

  def change do
    alter table(:hero_slides) do
      add :title_logo_url, :string
      add :channel_logo_url, :string
    end
  end
end
