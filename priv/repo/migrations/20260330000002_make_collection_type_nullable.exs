defmodule Marquee.Repo.Migrations.MakeCollectionTypeNullable do
  use Ecto.Migration

  def change do
    alter table(:collections) do
      modify :type, :string, null: true, from: {:string, null: false}
      modify :position, :integer, null: true, default: 0, from: {:integer, null: false}
    end
  end
end
