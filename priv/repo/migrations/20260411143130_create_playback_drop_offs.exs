defmodule Marquee.Repo.Migrations.CreatePlaybackDropOffs do
  use Ecto.Migration

  def change do
    create table(:playback_drop_offs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :video_id, references(:videos, type: :binary_id, on_delete: :delete_all), null: false
      add :viewer_id, references(:viewers, type: :binary_id, on_delete: :delete_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      add :bucket, :integer, null: false
      add :max_position, :float, null: false
      add :video_duration, :float
      add :left_at, :utc_datetime, null: false
      add :counted_at, :utc_datetime
      add :outcome, :string

      timestamps(type: :utc_datetime)
    end

    create index(:playback_drop_offs, [:organization_id])
    create index(:playback_drop_offs, [:video_id, :left_at])

    create index(:playback_drop_offs, [:left_at],
             where: "counted_at IS NULL",
             name: :playback_drop_offs_pending_left_at_index
           )

    create index(:playback_drop_offs, [:viewer_id, :video_id, :left_at],
             where: "viewer_id IS NOT NULL",
             name: :playback_drop_offs_viewer_return_index
           )

    create index(:playback_drop_offs, [:user_id, :video_id, :left_at],
             where: "user_id IS NOT NULL",
             name: :playback_drop_offs_user_return_index
           )

    create table(:video_drop_off_buckets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :video_id, references(:videos, type: :binary_id, on_delete: :delete_all), null: false
      add :bucket, :integer, null: false
      add :count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:video_drop_off_buckets, [:organization_id])
    create unique_index(:video_drop_off_buckets, [:video_id, :bucket])
  end
end
