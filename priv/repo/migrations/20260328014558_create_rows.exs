defmodule Marquee.Repo.Migrations.CreateRows do
  use Ecto.Migration

  def change do
    create table(:rows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :source_type, :string, null: false
      add :filter_config, :map
      add :position, :integer, null: false
      add :visible, :boolean, default: false, null: false

      add :organization_id, references(:organizations, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:rows, [:organization_id])
  end
end
