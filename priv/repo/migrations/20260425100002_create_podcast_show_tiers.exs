defmodule Bobine.Repo.Migrations.CreatePodcastShowTiers do
  use Ecto.Migration

  def change do
    create table(:podcast_show_tiers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :show_id,
          references(:podcast_shows, type: :binary_id, on_delete: :delete_all),
          null: false

      add :plan_id,
          references(:plans, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:podcast_show_tiers, [:organization_id])
    create index(:podcast_show_tiers, [:show_id])
    create unique_index(:podcast_show_tiers, [:show_id, :plan_id])
  end
end
