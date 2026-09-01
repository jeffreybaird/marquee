defmodule Marquee.Repo.Migrations.AddLoginBackgroundImageUrlToThemes do
  use Ecto.Migration

  def change do
    alter table(:themes) do
      add :login_background_image_url, :string
    end
  end
end
