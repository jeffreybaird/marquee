defmodule Marquee.Content.EpisodeFilteringTest do
  use Marquee.DataCase, async: true

  alias Marquee.Accounts.Scope
  alias Marquee.Catalog
  alias Marquee.Content
  alias Marquee.Content.Video

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

    # 3 standalone videos + 5 episode videos in 1 season of 1 series
    standalone_videos =
      for i <- 1..3 do
        insert(:video, organization: org, title: "Standalone #{i}", mux_status: "ready")
      end

    {:ok, series} = Content.create_series(scope, %{title: "Show"})
    {:ok, season} = Content.create_season(scope, series, %{title: "S1"})

    episode_videos =
      for i <- 1..5 do
        v = insert(:video, organization: org, title: "Episode #{i}", mux_status: "ready")
        {:ok, _} = Content.add_episode(scope, season, v, %{episode_number: i})
        v
      end

    %{
      org: org,
      scope: scope,
      series: series,
      season: season,
      standalone_videos: standalone_videos,
      episode_videos: episode_videos
    }
  end

  ## -----------------------------------------------------------------------
  ## exclude_episode_videos/1
  ## -----------------------------------------------------------------------

  describe "exclude_episode_videos/1" do
    test "filters out episode videos from a query", %{
      org: org,
      standalone_videos: standalone,
      episode_videos: episodes
    } do
      import Ecto.Query

      results =
        Video
        |> where(organization_id: ^org.id)
        |> Content.exclude_episode_videos()
        |> Marquee.Repo.all()

      result_ids = Enum.map(results, & &1.id) |> MapSet.new()
      standalone_ids = Enum.map(standalone, & &1.id) |> MapSet.new()
      episode_ids = Enum.map(episodes, & &1.id) |> MapSet.new()

      assert MapSet.equal?(result_ids, standalone_ids)
      assert MapSet.disjoint?(result_ids, episode_ids)
    end

    test "list_videos with exclude_episodes: true returns only standalone videos",
         %{org: org, standalone_videos: standalone} do
      %{results: results} = Content.list_videos(org, exclude_episodes: true)
      assert length(results) == length(standalone)
      Enum.each(results, fn v -> assert v.title =~ "Standalone" end)
    end

    test "list_videos without the option returns everything", %{org: org} do
      %{results: results} = Content.list_videos(org)
      assert length(results) == 8
    end
  end

  ## -----------------------------------------------------------------------
  ## :recent / :popular row resolvers
  ## -----------------------------------------------------------------------

  describe "auto-populated row resolvers" do
    test ":recent row excludes episode videos", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Recent",
          source_type: :recent,
          visible: true,
          max_items: 20
        })

      %{results: videos} = Catalog.resolve_row_content(org, row)

      assert length(videos) == 3
      Enum.each(videos, fn v -> assert v.title =~ "Standalone" end)
    end

    test ":popular row excludes episode videos", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Popular",
          source_type: :popular,
          visible: true,
          max_items: 20
        })

      %{results: videos} = Catalog.resolve_row_content(org, row)

      assert length(videos) == 3
      Enum.each(videos, fn v -> assert v.title =~ "Standalone" end)
    end

    test "videos reappear in :recent after being removed from a season",
         %{
           org: org,
           scope: scope,
           season: season,
           episode_videos: episodes
         } do
      removed = List.first(episodes)
      :ok = Content.remove_episode(scope, season, removed)

      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Recent",
          source_type: :recent,
          visible: true,
          max_items: 20
        })

      %{results: videos} = Catalog.resolve_row_content(org, row)
      ids = Enum.map(videos, & &1.id)

      assert removed.id in ids
      assert length(videos) == 4
    end
  end

  ## -----------------------------------------------------------------------
  ## :curated row does NOT filter
  ## -----------------------------------------------------------------------

  describe "curated rows" do
    test ":curated row includes episode videos when the operator added them",
         %{org: org, scope: scope, episode_videos: [ep1 | _]} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Hand-picked",
          source_type: :curated,
          visible: true,
          max_items: 20
        })

      {:ok, _} = Catalog.add_item_to_row(scope, row, ep1, 0)

      %{results: videos} = Catalog.resolve_row_content(org, row)
      assert Enum.any?(videos, &(&1.id == ep1.id))
    end
  end

  ## -----------------------------------------------------------------------
  ## Multi-tenant
  ## -----------------------------------------------------------------------

  describe "multi-tenant" do
    test "episode-exclusion subquery only considers episodes from the same query result",
         %{scope: scope} do
      # Create a foreign org with its own episode video
      other_org = insert(:organization)
      other_user = insert(:user)
      other_mem = insert(:membership, organization: other_org, user: other_user, role: :editor)
      other_scope = Scope.for_user(other_user) |> Scope.with_organization(other_org, other_mem)

      {:ok, other_series} = Content.create_series(other_scope, %{title: "Other"})
      {:ok, other_season} = Content.create_season(other_scope, other_series, %{title: "S1"})

      foreign_video =
        insert(:video, organization: other_org, title: "Foreign Episode", mux_status: "ready")

      {:ok, _} = Content.add_episode(other_scope, other_season, foreign_video)

      # Our org's standalone videos must still be visible to us; foreign org's
      # standalone videos must not appear in our org's :recent row
      _ = scope

      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Recent",
          source_type: :recent,
          visible: true,
          max_items: 20
        })

      %{results: videos} = Catalog.resolve_row_content(scope.organization, row)
      ids = Enum.map(videos, & &1.id)

      refute foreign_video.id in ids
    end
  end
end
