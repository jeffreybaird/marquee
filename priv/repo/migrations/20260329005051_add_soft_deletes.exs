defmodule Bobine.Repo.Migrations.AddSoftDeletes do
  use Ecto.Migration

  def change do
    tables = [
      :videos,
      :collections,
      :tags,
      :rows,
      :row_items,
      :watchlist_items,
      :favorites,
      :plans,
      :notifications,
      :webhook_endpoints,
      :organizations
    ]

    for table <- tables do
      alter table(table) do
        add :deleted_at, :utc_datetime
      end

      create index(table, [:deleted_at])
    end
  end
end
