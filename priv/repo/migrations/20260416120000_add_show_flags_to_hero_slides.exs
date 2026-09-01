defmodule Marquee.Repo.Migrations.AddShowFlagsToHeroSlides do
  use Ecto.Migration

  def change do
    alter table(:hero_slides) do
      add :show_headline, :boolean, null: false, default: true
      add :show_subheadline, :boolean, null: false, default: true
      add :show_description, :boolean, null: false, default: true
      add :show_brand_tag, :boolean, null: false, default: true
      add :show_primary_cta, :boolean, null: false, default: true
      add :show_secondary_cta, :boolean, null: false, default: true
    end
  end
end
