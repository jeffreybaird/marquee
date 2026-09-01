defmodule Marquee.Repo.Migrations.CreateLiveEventReminders do
  use Ecto.Migration

  def change do
    create table(:live_event_reminders, primary_key: false) do
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

      add :notified_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:live_event_reminders, [:live_event_id, :viewer_id])
    create index(:live_event_reminders, [:live_event_id])
    create index(:live_event_reminders, [:organization_id])
  end
end
