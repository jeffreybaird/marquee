defmodule Bobine.Repo.Migrations.RelaxPodcastAudioRequestEpisode do
  use Ecto.Migration

  def change do
    alter table(:podcast_audio_requests) do
      modify :episode_id, references(:podcast_episodes, type: :binary_id, on_delete: :delete_all),
        null: true,
        from: references(:podcast_episodes, type: :binary_id, on_delete: :delete_all)
    end
  end
end
