defmodule Marquee.Repo.Migrations.CreatePodcastEpisodes do
  use Ecto.Migration

  def change do
    create table(:podcast_episodes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :show_id,
          references(:podcast_shows, type: :binary_id, on_delete: :delete_all),
          null: false

      # Stable GUID used by podcast clients for episode identity. For remote
      # feeds, this is the upstream <guid>; for direct uploads, generated.
      add :guid, :string, null: false

      add :title, :string, null: false
      add :description, :text
      add :episode_number, :integer
      add :season_number, :integer
      # episode_type: "full" | "trailer" | "bonus"
      add :episode_type, :string, default: "full", null: false
      add :publish_date, :utc_datetime
      add :duration_seconds, :integer
      add :explicit, :boolean

      # Audio source — exactly one of these is populated based on the show's
      # source_type, except when remote audio has been mirrored to Mux for
      # caching, in which case both may be populated.
      add :mux_asset_id, :string
      add :mux_playback_id, :string
      add :mux_upload_id, :string
      add :mux_status, :string
      # MP3 bytes once the static rendition is ready (Mux mp3_support).
      add :mp3_byte_size, :integer

      add :remote_audio_url, :string
      add :remote_audio_byte_size, :integer
      add :remote_audio_content_type, :string

      # Local overrides for feed-import episodes. When :overrides_locked is
      # true, the periodic sync leaves the listed fields alone.
      add :overrides_locked, :boolean, default: false, null: false
      add :locked_fields, {:array, :string}, default: []

      # Episode lifecycle:
      #   "draft" | "processing" | "published" | "withdrawn" | "errored"
      add :status, :string, null: false, default: "draft"

      add :error_message, :text
      add :withdrawn_at, :utc_datetime
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:podcast_episodes, [:organization_id])
    create index(:podcast_episodes, [:show_id])
    create unique_index(:podcast_episodes, [:show_id, :guid])
    create index(:podcast_episodes, [:show_id, :publish_date])
    create index(:podcast_episodes, [:mux_asset_id])
    create index(:podcast_episodes, [:mux_upload_id])
    create index(:podcast_episodes, [:status])
  end
end
