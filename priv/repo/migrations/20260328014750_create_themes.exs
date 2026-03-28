defmodule Bobine.Repo.Migrations.CreateThemes do
  use Ecto.Migration

  def change do
    create table(:themes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :brand_primary, :string
      add :brand_secondary, :string
      add :background, :string
      add :surface, :string
      add :text_primary, :string
      add :text_secondary, :string
      add :accent, :string
      add :font_heading, :string
      add :font_body, :string
      add :border_radius, :string
      add :card_border_radius, :string
      add :logo_url, :string
      add :favicon_url, :string
      add :organization_id, references(:organizations, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:themes, [:organization_id])
  end
end
