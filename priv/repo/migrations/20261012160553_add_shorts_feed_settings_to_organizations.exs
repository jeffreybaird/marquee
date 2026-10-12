defmodule Marquee.Repo.Migrations.AddShortsFeedSettingsToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :shorts_feed_enabled, :boolean, default: false, null: false
      add :shorts_feed_access, :string, default: "subscribers_only", null: false
    end
  end
end
