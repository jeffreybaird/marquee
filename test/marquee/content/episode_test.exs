defmodule Marquee.Content.EpisodeTest do
  use Marquee.DataCase

  alias Marquee.Content.Episode

  describe "changeset/2" do
    test "with valid attrs succeeds" do
      video = insert(:video)

      changeset =
        Episode.changeset(%Episode{}, %{episode_number: 1, video_id: video.id})

      assert changeset.valid?
    end

    test "without episode_number fails" do
      video = insert(:video)
      changeset = Episode.changeset(%Episode{}, %{video_id: video.id})
      refute changeset.valid?
      assert %{episode_number: ["can't be blank"]} = errors_on(changeset)
    end

    test "without video_id fails" do
      changeset = Episode.changeset(%Episode{}, %{episode_number: 1})
      refute changeset.valid?
      assert %{video_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "episode_number must be > 0" do
      video = insert(:video)

      changeset =
        Episode.changeset(%Episode{}, %{episode_number: 0, video_id: video.id})

      refute changeset.valid?
      assert %{episode_number: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "episode_number unique within season" do
      season = insert(:season)
      video_a = insert(:video, organization: season.organization)
      video_b = insert(:video, organization: season.organization)

      insert(:episode,
        season: season,
        organization: season.organization,
        video: video_a,
        episode_number: 1
      )

      {:error, changeset} =
        %Episode{
          organization_id: season.organization.id,
          season_id: season.id
        }
        |> Episode.changeset(%{episode_number: 1, video_id: video_b.id})
        |> Repo.insert()

      assert %{season_id: _} = errors_on(changeset)
    end

    test "video_id unique within season (can't add same video twice)" do
      season = insert(:season)
      video = insert(:video, organization: season.organization)

      insert(:episode,
        season: season,
        organization: season.organization,
        video: video,
        episode_number: 1
      )

      {:error, changeset} =
        %Episode{
          organization_id: season.organization.id,
          season_id: season.id
        }
        |> Episode.changeset(%{episode_number: 2, video_id: video.id})
        |> Repo.insert()

      assert %{season_id: _} = errors_on(changeset)
    end

    test "same video in different seasons is allowed" do
      org = insert(:organization)
      series = insert(:series, organization: org)
      season_a = insert(:season, series: series, organization: org, season_number: 1)
      season_b = insert(:season, series: series, organization: org, season_number: 2)
      video = insert(:video, organization: org)

      insert(:episode,
        season: season_a,
        organization: org,
        video: video,
        episode_number: 1
      )

      assert {:ok, _} =
               %Episode{organization_id: org.id, season_id: season_b.id}
               |> Episode.changeset(%{episode_number: 1, video_id: video.id})
               |> Repo.insert()
    end
  end
end
