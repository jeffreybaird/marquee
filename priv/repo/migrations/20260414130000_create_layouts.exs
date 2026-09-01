defmodule Marquee.Repo.Migrations.CreateLayouts do
  use Ecto.Migration

  def change do
    create table(:layouts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :preset_name, :string, null: false
      add :default_browse_card_variant, :string, null: false
      add :rows, {:array, :map}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:layouts, [:organization_id])
  end
end
