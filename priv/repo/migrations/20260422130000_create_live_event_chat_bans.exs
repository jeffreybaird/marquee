defmodule Marquee.Repo.Migrations.CreateLiveEventChatBans do
  use Ecto.Migration

  def change do
    create table(:live_event_chat_bans, primary_key: false) do
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

      add :banned_by_user_id,
          references(:users, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:live_event_chat_bans, [:live_event_id, :viewer_id])
    create index(:live_event_chat_bans, [:organization_id])
  end
end
