defmodule Marquee.Repo.Migrations.CreateLiveEvents do
  use Ecto.Migration

  def change do
    create table(:live_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :title, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :cover_image_url, :string
      add :scheduled_start_at, :utc_datetime, null: false
      add :estimated_duration_minutes, :integer
      add :access_type, :string, null: false, default: "subscribers_only"
      add :ppv_price_cents, :integer
      add :ppv_access_window_hours, :integer, default: 48
      add :status, :string, null: false, default: "draft"
      add :mux_live_stream_id, :string
      add :mux_live_playback_id, :string
      add :mux_rtmp_url, :string

      add :recording_video_id,
          references(:videos, type: :binary_id, on_delete: :nilify_all)

      add :stripe_product_id, :string
      add :stripe_price_id, :string
      add :went_live_at, :utc_datetime
      add :ended_at, :utc_datetime
      add :canceled_at, :utc_datetime
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:live_events, [:organization_id])
    create index(:live_events, [:organization_id, :scheduled_start_at])
    create index(:live_events, [:organization_id, :status])
    create unique_index(:live_events, [:slug, :organization_id])
    create index(:live_events, [:mux_live_stream_id])
    create index(:live_events, [:recording_video_id])
  end
end
