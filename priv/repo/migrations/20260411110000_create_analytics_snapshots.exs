defmodule Bobine.Repo.Migrations.CreateAnalyticsSnapshots do
  use Ecto.Migration

  def change do
    create table(:analytics_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :period_date, :date, null: false
      add :metric_type, :string, null: false
      add :value, :decimal, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:analytics_snapshots, [:organization_id])
    create unique_index(:analytics_snapshots, [:organization_id, :period_date, :metric_type])
  end
end
