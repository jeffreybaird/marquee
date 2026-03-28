defmodule Bobine.Repo.Migrations.CreateWebhookEndpoints do
  use Ecto.Migration

  def change do
    create table(:webhook_endpoints, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :url, :string, null: false
      add :secret, :string, null: false
      add :events, {:array, :string}, null: false
      add :active, :boolean, default: false, null: false
      add :organization_id, references(:organizations, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:webhook_endpoints, [:organization_id])
  end
end
