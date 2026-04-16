defmodule Bobine.Repo.Migrations.AddAdminAccentToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :admin_accent_color, :string
    end
  end
end
