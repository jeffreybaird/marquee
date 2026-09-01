defmodule Marquee.Repo.Migrations.CreateRowItems do
  use Ecto.Migration

  def change do
    create table(:row_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :integer, null: false
      add :row_id, references(:rows, on_delete: :delete_all, type: :binary_id), null: false
      add :video_id, references(:videos, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:row_items, [:row_id])
    create index(:row_items, [:video_id])
  end
end
