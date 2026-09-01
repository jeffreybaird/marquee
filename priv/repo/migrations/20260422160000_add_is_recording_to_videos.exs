defmodule Marquee.Repo.Migrations.AddIsRecordingToVideos do
  use Ecto.Migration

  def change do
    alter table(:videos) do
      add :is_recording, :boolean, null: false, default: false
    end
  end
end
