defmodule Bobine.Repo.Migrations.CreateChatMessages do
  use Ecto.Migration

  def change do
    create table(:chat_messages, primary_key: false) do
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

      add :content, :text, null: false

      add :deleted_at, :utc_datetime

      add :deleted_by_user_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:chat_messages, [:organization_id, :live_event_id])
    create index(:chat_messages, [:live_event_id, :inserted_at])
    create index(:chat_messages, [:viewer_id])
  end
end
