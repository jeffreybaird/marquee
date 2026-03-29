defmodule Bobine.Repo.Migrations.AddSuperAdminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_super_admin, :boolean, default: false, null: false
    end
  end
end
