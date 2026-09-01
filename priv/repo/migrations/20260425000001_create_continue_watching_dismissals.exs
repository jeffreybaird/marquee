defmodule Marquee.Repo.Migrations.CreateContinueWatchingDismissals do
  use Ecto.Migration

  def change do
    create table(:continue_watching_dismissals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :dismissed_at, :utc_datetime, null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :viewer_id, references(:viewers, type: :binary_id, on_delete: :delete_all), null: false
      add :video_id, references(:videos, type: :binary_id, on_delete: :delete_all), null: true
      add :series_id, references(:series, type: :binary_id, on_delete: :delete_all), null: true

      timestamps(type: :utc_datetime)
    end

    # Exactly one of video_id or series_id must be set.
    create constraint(:continue_watching_dismissals, :exactly_one_target,
             check: "(video_id IS NOT NULL)::int + (series_id IS NOT NULL)::int = 1"
           )

    create index(:continue_watching_dismissals, [:organization_id, :viewer_id])

    create unique_index(:continue_watching_dismissals, [:viewer_id, :video_id, :organization_id],
             where: "video_id IS NOT NULL",
             name: :continue_watching_dismissals_viewer_video_org_unique
           )

    create unique_index(:continue_watching_dismissals, [:viewer_id, :series_id, :organization_id],
             where: "series_id IS NOT NULL",
             name: :continue_watching_dismissals_viewer_series_org_unique
           )
  end
end
