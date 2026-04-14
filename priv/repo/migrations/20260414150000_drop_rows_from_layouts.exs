defmodule Bobine.Repo.Migrations.DropRowsFromLayouts do
  use Ecto.Migration

  def change do
    alter table(:layouts) do
      remove :rows, {:array, :map}, default: []
    end
  end
end
