defmodule Marquee.Repo.Migrations.AddViewerThemeFieldsToThemes do
  use Ecto.Migration

  def change do
    alter table(:themes) do
      add :elevated, :string
      add :text_on_accent, :string
      add :brand_primary_hover, :string
      add :border_color, :string
      add :divider_color, :string
      add :nav_background, :string
      add :card_background, :string
      add :overlay_color, :string
    end
  end
end
