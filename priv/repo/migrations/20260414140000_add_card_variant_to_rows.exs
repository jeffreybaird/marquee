defmodule Bobine.Repo.Migrations.AddCardVariantToRows do
  use Ecto.Migration

  def change do
    alter table(:rows) do
      add :card_variant, :string
    end
  end
end
