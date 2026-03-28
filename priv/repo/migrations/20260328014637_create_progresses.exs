defmodule Bobine.Repo.Migrations.CreateProgresses do
  use Ecto.Migration

  def change do
    create table(:progresses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :float, null: false
      add :completed, :boolean, default: false, null: false
      add :organization_id, references(:organizations, on_delete: :delete_all, type: :binary_id), null: false
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :video_id, references(:videos, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:progresses, [:organization_id])
    create index(:progresses, [:user_id])
    create index(:progresses, [:video_id])
    create unique_index(:progresses, [:user_id, :video_id, :organization_id])
  end
end
