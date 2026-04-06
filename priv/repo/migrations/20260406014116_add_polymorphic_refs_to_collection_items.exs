defmodule Bobine.Repo.Migrations.AddPolymorphicRefsToCollectionItems do
  use Ecto.Migration

  def change do
    alter table(:collection_items) do
      add :season_id, references(:seasons, type: :binary_id, on_delete: :nothing)
      add :series_id, references(:series, type: :binary_id, on_delete: :nothing)
      add :item_type, :string
    end

    create index(:collection_items, [:collection_id, :item_type])
    create index(:collection_items, [:season_id])
    create index(:collection_items, [:series_id])

    # Make video_id nullable — items can now reference a season or series instead
    alter table(:collection_items) do
      modify :video_id, :binary_id, null: true, from: {:binary_id, null: false}
    end
  end
end
