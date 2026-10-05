defmodule Marquee.Repo.Migrations.AddAdminDemoSandboxes do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :demo_kind, :string
      add :demo_expires_at, :utc_datetime_usec
      add :demo_purged_at, :utc_datetime_usec
      add :demo_entry_key_hash, :binary
    end

    create unique_index(:organizations, [:demo_entry_key_hash])
    create index(:organizations, [:demo_kind, :demo_expires_at])

    alter table(:users) do
      add :demo_kind, :string
      add :demo_revoked_at, :utc_datetime_usec
    end

    create table(:admin_demo_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id), null: false
      add :user_id, references(:users, type: :binary_id), null: false
      add :owner_user_id, references(:users, type: :binary_id), null: false
      add :token_hash, :binary, null: false
      add :entry_key_hash, :binary, null: false
      add :hostname, :string, null: false
      add :template_version, :string, null: false
      add :generation, :binary_id, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      add :purged_at, :utc_datetime_usec
      add :replacement_session_id, references(:admin_demo_sessions, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:admin_demo_sessions, [:token_hash])
    create unique_index(:admin_demo_sessions, [:entry_key_hash])
    create unique_index(:admin_demo_sessions, [:organization_id])
    create index(:admin_demo_sessions, [:expires_at])

    create table(:admin_demo_protected_assets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mux_asset_id, :string, null: false
      add :mux_playback_id, :string, null: false
      add :template_version, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:admin_demo_protected_assets, [:mux_asset_id])
  end
end
