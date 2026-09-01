defmodule Marquee.Repo.Migrations.AddCardDisplayOptionsToRows do
  use Ecto.Migration

  def change do
    alter table(:rows) do
      # When false, the details bar beneath each card's image is suppressed
      # (title, metadata, etc.). Default keeps the historical rendering.
      add :show_details, :boolean, default: true, null: false

      # When true AND show_details is false, the card's title is overlaid
      # on top of the thumbnail instead. Ignored when show_details is true.
      add :title_overlay, :boolean, default: false, null: false
    end
  end
end
