defmodule Bobine.Repo.Migrations.CreateSeries do
  use Ecto.Migration

  def change do
    create table(:series, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :nothing),
          null: false

      add :title, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :cover_image_url, :string
      add :position, :integer, default: 0, null: false
      add :visible, :boolean, default: true, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:series, [:organization_id, :slug])
    create index(:series, [:organization_id])
  end
end
