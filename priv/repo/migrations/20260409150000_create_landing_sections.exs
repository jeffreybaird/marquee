defmodule Marquee.Repo.Migrations.CreateLandingSections do
  use Ecto.Migration

  def change do
    create table(:landing_sections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :section_type, :string, null: false
      add :position, :integer, null: false, default: 0
      add :visible, :boolean, null: false, default: true
      add :config, :map, null: false, default: %{}
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:landing_sections, [:organization_id])
    create index(:landing_sections, [:organization_id, :position])
  end
end
