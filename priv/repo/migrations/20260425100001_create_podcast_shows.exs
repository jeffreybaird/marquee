defmodule Bobine.Repo.Migrations.CreatePodcastShows do
  use Ecto.Migration

  def change do
    create table(:podcast_shows, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      # Source — fixed for the lifetime of the show
      add :source_type, :string, null: false, default: "direct_upload"
      add :remote_feed_url, :string
      add :remote_last_synced_at, :utc_datetime
      add :remote_last_sync_error, :text
      add :remote_consecutive_failures, :integer, default: 0, null: false

      # Core podcast metadata
      add :title, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :author, :string
      add :owner_name, :string
      add :owner_email, :string
      add :language, :string, default: "en-us"
      add :primary_category, :string
      add :secondary_categories, {:array, :string}, default: []
      add :explicit, :boolean, default: false, null: false
      add :copyright, :string
      add :cover_artwork_url, :string

      # Access configuration
      # access_mode: "any_active" | "specific_tiers" | "audio_only_plan"
      add :access_mode, :string, null: false, default: "any_active"

      add :audio_only_plan_id,
          references(:plans, type: :binary_id, on_delete: :nilify_all)

      # Lifecycle
      add :published, :boolean, default: false, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:podcast_shows, [:organization_id])
    create unique_index(:podcast_shows, [:organization_id, :slug])
    create index(:podcast_shows, [:organization_id, :access_mode])
    create index(:podcast_shows, [:source_type])
  end
end
