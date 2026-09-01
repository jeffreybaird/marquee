defmodule Marquee.Repo.Migrations.CreateWebhookDeliveries do
  use Ecto.Migration

  def change do
    create table(:webhook_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :payload, :map, null: false
      add :response_status, :integer
      add :response_body, :text
      add :attempts, :integer, null: false, default: 0
      add :delivered_at, :utc_datetime

      add :endpoint_id, references(:webhook_endpoints, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:webhook_deliveries, [:endpoint_id])
  end
end
