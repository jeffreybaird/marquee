defmodule Marquee.Repo.Migrations.CreateVideos do
  use Ecto.Migration

  def change do
    create table(:videos, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :mux_asset_id, :string
      add :mux_playback_id, :string
      add :mux_upload_id, :string
      add :mux_status, :string
      add :duration, :float
      add :max_resolution, :string
      add :published, :boolean, default: false, null: false

      add :organization_id, references(:organizations, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:videos, [:organization_id])
  end
end
