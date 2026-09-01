defmodule Marquee.Repo.Migrations.CreatePodcastFeedTokens do
  use Ecto.Migration

  def change do
    create table(:podcast_feed_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :show_id,
          references(:podcast_shows, type: :binary_id, on_delete: :delete_all),
          null: false

      add :viewer_id,
          references(:viewers, type: :binary_id, on_delete: :delete_all),
          null: false

      # Random opaque, URL-safe token (32 bytes encoded). Unguessable.
      add :token, :string, null: false

      # Status: "active" | "revoked". Tokens are never hard-deleted so that
      # the audit log of access remains intact.
      add :status, :string, null: false, default: "active"

      add :expires_at, :utc_datetime
      add :revoked_at, :utc_datetime
      add :revoked_reason, :string
      add :last_used_at, :utc_datetime
      add :request_count, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:podcast_feed_tokens, [:organization_id])
    create unique_index(:podcast_feed_tokens, [:token])

    # A given subscriber can have at most one active token per show.
    # Revoked tokens are unconstrained so old tokens linger as audit trail.
    create unique_index(:podcast_feed_tokens, [:show_id, :viewer_id],
             where: "status = 'active'",
             name: :podcast_feed_tokens_active_show_viewer_index
           )

    create index(:podcast_feed_tokens, [:viewer_id, :status])
    create index(:podcast_feed_tokens, [:show_id, :status])
  end
end
