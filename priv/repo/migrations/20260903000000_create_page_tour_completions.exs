defmodule Marquee.Repo.Migrations.CreatePageTourCompletions do
  use Ecto.Migration

  def change do
    create table(:page_tour_completions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :page_key, :string, null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    # One "seen" record per operator (or subscriber), per organization, per page.
    create unique_index(:page_tour_completions, [:user_id, :organization_id, :page_key],
             name: :page_tour_completions_user_org_page_unique
           )

    # Tenant-scoped reads (e.g. tour-completion analytics for one org).
    create index(:page_tour_completions, [:organization_id])
  end
end
