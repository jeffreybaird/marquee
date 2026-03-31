defmodule Bobine.Repo.Migrations.CreateViewersAndTokens do
  use Ecto.Migration

  def change do
    # ------------------------------------------------------------------
    # Viewers — completely separate identity from User (operators)
    # ------------------------------------------------------------------
    create table(:viewers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      # Identity
      add :email, :string, null: false
      add :display_name, :string
      add :avatar_url, :string

      # Auth
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime

      # Account state
      add :status, :string, null: false, default: "active"

      # Subscription gating (Stripe integration in Feature 05)
      add :subscription_status, :string, null: false, default: "none"
      add :subscription_expires_at, :utc_datetime
      add :trial_expires_at, :utc_datetime

      # Profile
      add :onboarding_completed, :boolean, default: false
      add :marketing_opt_in, :boolean, default: false
      add :metadata, :map, default: %{}

      # Soft delete
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:viewers, [:organization_id, :email])
    create index(:viewers, [:organization_id])
    create index(:viewers, [:email])
    create index(:viewers, [:organization_id, :subscription_status])

    # ------------------------------------------------------------------
    # Viewer tokens — separate from UserToken / users_tokens
    # ------------------------------------------------------------------
    create table(:viewer_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :viewer_id, references(:viewers, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:viewer_tokens, [:token, :context])
    create index(:viewer_tokens, [:viewer_id])

    # ------------------------------------------------------------------
    # Add viewer_id to engagement schemas (alongside existing user_id)
    # ------------------------------------------------------------------
    alter table(:subscriptions) do
      add :viewer_id, references(:viewers, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:watch_histories) do
      add :viewer_id, references(:viewers, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:progresses) do
      add :viewer_id, references(:viewers, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:watchlist_items) do
      add :viewer_id, references(:viewers, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:favorites) do
      add :viewer_id, references(:viewers, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:analytics_events) do
      add :viewer_id, references(:viewers, type: :binary_id, on_delete: :nilify_all)
    end

    # ------------------------------------------------------------------
    # Add visibility to videos
    # ------------------------------------------------------------------
    alter table(:videos) do
      add :visibility, :string, default: "subscribers_only"
    end
  end
end
