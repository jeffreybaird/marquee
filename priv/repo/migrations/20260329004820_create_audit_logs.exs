defmodule Bobine.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :uuid
      add :changes, :map, default: %{}
      add :metadata, :map, default: %{}
      add :organization_id, references(:organizations, on_delete: :nothing, type: :binary_id)
      add :user_id, references(:users, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_logs, [:organization_id])
    create index(:audit_logs, [:user_id])
    create index(:audit_logs, [:action])
    create index(:audit_logs, [:resource_type, :resource_id])
  end
end
