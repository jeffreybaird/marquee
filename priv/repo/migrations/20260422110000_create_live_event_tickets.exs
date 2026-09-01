defmodule Marquee.Repo.Migrations.CreateLiveEventTickets do
  use Ecto.Migration

  def change do
    create table(:live_event_tickets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :live_event_id,
          references(:live_events, type: :binary_id, on_delete: :delete_all),
          null: false

      add :viewer_id,
          references(:viewers, type: :binary_id, on_delete: :delete_all),
          null: false

      add :stripe_payment_intent_id, :string
      add :stripe_charge_id, :string
      add :amount_cents, :integer, null: false
      add :access_starts_at, :utc_datetime, null: false
      add :access_ends_at, :utc_datetime, null: false
      add :refunded_at, :utc_datetime
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:live_event_tickets, [:organization_id])
    create index(:live_event_tickets, [:live_event_id])
    create unique_index(:live_event_tickets, [:live_event_id, :viewer_id])
    create index(:live_event_tickets, [:viewer_id])
  end
end
