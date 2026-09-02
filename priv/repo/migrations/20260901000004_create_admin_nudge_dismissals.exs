defmodule Marquee.Repo.Migrations.CreateAdminNudgeDismissals do
  use Ecto.Migration

  def change do
    create table(:admin_nudge_dismissals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :nudge_key, :string, null: false
      add :dismissed_at, :utc_datetime, null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:admin_nudge_dismissals, [:user_id, :organization_id, :nudge_key],
             name: :admin_nudge_dismissals_user_org_key_unique
           )
  end
end
