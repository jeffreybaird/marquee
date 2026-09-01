defmodule Marquee.Repo.Migrations.CreatePodcastAudioRequests do
  use Ecto.Migration

  def change do
    # Append-only delivery log used for per-show analytics: download counts,
    # unique listener counts. Populated by the audio proxy / feed handlers
    # via the analytics buffer (bulk queue).
    create table(:podcast_audio_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :show_id,
          references(:podcast_shows, type: :binary_id, on_delete: :delete_all),
          null: false

      add :episode_id,
          references(:podcast_episodes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :viewer_id,
          references(:viewers, type: :binary_id, on_delete: :nilify_all)

      add :feed_token_id,
          references(:podcast_feed_tokens, type: :binary_id, on_delete: :nilify_all)

      add :request_type, :string, null: false
      add :user_agent, :string
      add :occurred_at, :utc_datetime, null: false
    end

    create index(:podcast_audio_requests, [:organization_id])
    create index(:podcast_audio_requests, [:show_id, :occurred_at])
    create index(:podcast_audio_requests, [:episode_id, :occurred_at])
    create index(:podcast_audio_requests, [:show_id, :viewer_id])
  end
end
