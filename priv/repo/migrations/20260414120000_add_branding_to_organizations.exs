defmodule Marquee.Repo.Migrations.AddBrandingToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :accent_color_base, :string
      add :accent_color_hover, :string
      add :accent_color_active, :string
      add :accent_color_subtle, :string
      add :display_font, :string
      add :preset_name, :string
    end
  end
end
