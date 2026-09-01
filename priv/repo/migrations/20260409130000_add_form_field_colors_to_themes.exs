defmodule Marquee.Repo.Migrations.AddFormFieldColorsToThemes do
  use Ecto.Migration

  def change do
    alter table(:themes) do
      add :form_text, :string
      add :form_placeholder, :string
    end
  end
end
