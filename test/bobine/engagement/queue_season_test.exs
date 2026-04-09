defmodule Bobine.Engagement.QueueSeasonTest do
  use Bobine.DataCase, async: true

  alias Bobine.Accounts.Scope
  alias Bobine.Content
  alias Bobine.Engagement

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    viewer = insert(:subscribed_viewer, organization: org)

    {:ok, series} = Content.create_series(scope, %{title: "Show"})
    {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})

    videos =
      for i <- 1..4 do
        v = insert(:video, organization: org, title: "Episode #{i}", mux_status: "ready")
        {:ok, _} = Content.add_episode(scope, season, v, %{episode_number: i})
        v
      end

    %{
      org: org,
      scope: scope,
      viewer: viewer,
      season: season,
      series: series,
      episode_videos: videos
    }
  end

  ## -----------------------------------------------------------------------
  ## add_videos_to_queue_end/3
  ## -----------------------------------------------------------------------

  describe "add_videos_to_queue_end/3" do
    test "appends videos in order after existing items",
         %{org: org, viewer: viewer, episode_videos: videos} do
      [v1, v2, v3, _] = videos

      # Existing item via the existing API
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)

      assert {:ok, 2} = Engagement.add_videos_to_queue_end(org, viewer, [v2, v3])

      queue = Engagement.list_queue(org, viewer)
      assert Enum.map(queue, & &1.video_id) == [v1.id, v2.id, v3.id]
      assert Enum.map(queue, & &1.position) == [0, 1, 2]
    end

    test "skips videos already in the queue", %{org: org, viewer: viewer, episode_videos: videos} do
      [v1, v2, _, _] = videos
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)

      assert {:ok, 1} = Engagement.add_videos_to_queue_end(org, viewer, [v1, v2])

      queue = Engagement.list_queue(org, viewer)
      assert length(queue) == 2
    end

    test "returns {:ok, 0} when nothing to add", %{org: org, viewer: viewer} do
      assert {:ok, 0} = Engagement.add_videos_to_queue_end(org, viewer, [])
    end
  end

  ## -----------------------------------------------------------------------
  ## add_videos_to_queue_beginning/3
  ## -----------------------------------------------------------------------

  describe "add_videos_to_queue_beginning/3" do
    test "shifts existing items down and inserts new at the front",
         %{org: org, viewer: viewer, episode_videos: videos} do
      [v1, v2, v3, v4] = videos

      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)

      assert {:ok, 2} = Engagement.add_videos_to_queue_beginning(org, viewer, [v3, v4])

      queue = Engagement.list_queue(org, viewer)
      assert Enum.map(queue, & &1.video_id) == [v3.id, v4.id, v1.id, v2.id]
      assert Enum.map(queue, & &1.position) == [0, 1, 2, 3]
    end

    test "skips duplicates", %{org: org, viewer: viewer, episode_videos: videos} do
      [v1, v2, v3, _] = videos
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)

      assert {:ok, 2} = Engagement.add_videos_to_queue_beginning(org, viewer, [v2, v3, v1])

      queue = Engagement.list_queue(org, viewer)
      assert length(queue) == 3
      # v1 should still appear, originally last; the two new ones lead.
      assert Enum.map(queue, & &1.video_id) == [v2.id, v3.id, v1.id]
    end

    test "returns {:ok, 0} when nothing to add", %{org: org, viewer: viewer} do
      assert {:ok, 0} = Engagement.add_videos_to_queue_beginning(org, viewer, [])
    end
  end

  ## -----------------------------------------------------------------------
  ## has_season_progress?/3
  ## -----------------------------------------------------------------------

  describe "has_season_progress?/3" do
    test "returns false when viewer has no progress",
         %{org: org, viewer: viewer, season: season} do
      refute Engagement.has_season_progress?(org, viewer, season)
    end

    test "returns true when viewer has any progress on any episode",
         %{org: org, viewer: viewer, season: season, episode_videos: [v1 | _]} do
      insert(:progress,
        organization: org,
        viewer: viewer,
        video: v1,
        position: 50.0,
        completed: false
      )

      assert Engagement.has_season_progress?(org, viewer, season)
    end

    test "scoped to org", %{viewer: viewer, season: season} do
      other_org = insert(:organization)
      refute Engagement.has_season_progress?(other_org, viewer, season)
    end
  end
end
