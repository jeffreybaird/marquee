defmodule Bobine.Repo.Migrations.CreateFavorites do
  use Ecto.Migration

  def change do
    create table(:favorites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, on_delete: :delete_all, type: :binary_id), null: false
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :video_id, references(:videos, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:favorites, [:organization_id])
    create index(:favorites, [:user_id])
    create index(:favorites, [:video_id])
    create unique_index(:favorites, [:user_id, :video_id, :organization_id])
  end
end
