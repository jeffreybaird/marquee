defmodule Bobine.Repo.Migrations.CreateHeroSlides do
  use Ecto.Migration

  def change do
    create table(:hero_slides, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :row_id, references(:rows, type: :binary_id, on_delete: :delete_all), null: false
      add :video_id, references(:videos, type: :binary_id, on_delete: :delete_all), null: false

      add :position, :integer, null: false, default: 0

      # Custom overlay text — operator-written, overrides video defaults
      add :headline, :string
      add :subheadline, :string
      add :brand_tag, :string
      add :description, :text
      add :primary_cta_label, :string
      add :secondary_cta_label, :string

      # Optional custom background image
      add :background_image_url, :string

      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:hero_slides, [:organization_id])
    create unique_index(:hero_slides, [:row_id, :video_id], where: "deleted_at IS NULL")

    create constraint(:hero_slides, :position_range, check: "position >= 0 AND position <= 3")
  end
end
