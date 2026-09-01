defmodule Marquee.Repo.Migrations.BackfillCollectionItemTypes do
  use Ecto.Migration

  def up do
    execute """
    UPDATE collection_items
    SET item_type = 'video'
    WHERE item_type IS NULL
    """

    alter table(:collection_items) do
      modify :item_type, :string, null: false
    end
  end

  def down do
    alter table(:collection_items) do
      modify :item_type, :string, null: true
    end
  end
end
