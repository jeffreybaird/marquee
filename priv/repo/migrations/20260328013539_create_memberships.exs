defmodule Marquee.Repo.Migrations.CreateMemberships do
  use Ecto.Migration

  def change do
    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      add :organization_id, references(:organizations, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:memberships, [:user_id])
    create index(:memberships, [:organization_id])
    create unique_index(:memberships, [:user_id, :organization_id])
  end
end
