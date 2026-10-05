defmodule Marquee.Repo.Migrations.AddTenantDomainProvisioning do
  use Ecto.Migration

  def change do
    create table(:tenant_domains, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :hostname, :string, null: false
      add :host_pattern, :string, null: false
      add :dns_zone, :string, null: false
      add :target_ipv4, :string, null: false
      add :dns_record_id, :string
      add :generation, :binary_id, null: false
      add :status, :string, null: false, default: "pending_dns"
      add :eligibility_source, :string, null: false
      add :eligible_at, :utc_datetime_usec, null: false
      add :last_error, :string
      add :ready_at, :utc_datetime_usec
      add :lease_token, :binary_id
      add :lease_expires_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenant_domains, [:organization_id])
    create unique_index(:tenant_domains, [:hostname])
    create index(:tenant_domains, [:status])
  end
end
