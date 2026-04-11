defmodule Bobine.Repo.Migrations.AddAuditLogQueryIndexes do
  use Ecto.Migration

  def change do
    create index(:audit_logs, [:organization_id, :inserted_at])
    create index(:audit_logs, [:organization_id, :action, :inserted_at])
    create index(:audit_logs, [:user_id, :inserted_at])
  end
end
