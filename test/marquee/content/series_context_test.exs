defmodule Marquee.Content.SeriesContextTest do
  use Marquee.DataCase

  alias Marquee.Accounts.Scope
  alias Marquee.Content

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    %{org: org, scope: scope}
  end

  ## -----------------------------------------------------------------------
  ## Series CRUD
  ## -----------------------------------------------------------------------

  describe "create_series/2" do
    test "creates with auto-generated slug", %{scope: scope} do
      assert {:ok, series} = Content.create_series(scope, %{title: "My Great Series"})
      assert series.title == "My Great Series"
      assert series.slug == "my-great-series"
      assert series.organization_id == scope.organization.id
    end

    test "broadcasts :series_created event", %{org: org, scope: scope} do
      Marquee.Events.subscribe(org.id)
      {:ok, series} = Content.create_series(scope, %{title: "Event Test"})
      assert_receive {:marquee_event, {:series_created, ^series}, _scope}
    end

    test "creates audit log entry", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Audit Test"})

      assert Repo.get_by(Marquee.Audit.Log,
               action: "series.created",
               resource_id: series.id
             )
    end
  end

  describe "list_series/2" do
    test "returns series for the org, ordered by position", %{org: org, scope: scope} do
      {:ok, s2} = Content.create_series(scope, %{title: "Second", position: 1})
      {:ok, s1} = Content.create_series(scope, %{title: "First", position: 0})

      assert %{results: [first, second]} = Content.list_series(org)
      assert first.id == s1.id
      assert second.id == s2.id
    end

    test "excludes soft-deleted series", %{org: org, scope: scope} do
      {:ok, active} = Content.create_series(scope, %{title: "Active"})
      {:ok, deleted} = Content.create_series(scope, %{title: "Deleted"})
      {:ok, _} = Content.delete_series(scope, deleted)

      assert %{results: [found]} = Content.list_series(org)
      assert found.id == active.id
    end

    test "does not return series from other orgs", %{org: org, scope: scope} do
      {:ok, _} = Content.create_series(scope, %{title: "Our Series"})

      other_org = insert(:organization)
      other_user = insert(:user)
      other_mem = insert(:membership, organization: other_org, user: other_user, role: :editor)
      other_scope = Scope.for_user(other_user) |> Scope.with_organization(other_org, other_mem)
      {:ok, _} = Content.create_series(other_scope, %{title: "Their Series"})

      assert %{results: results} = Content.list_series(org)
      assert length(results) == 1
    end

    test "returns pagination struct", %{org: org, scope: scope} do
      {:ok, _} = Content.create_series(scope, %{title: "First"})

      result = Content.list_series(org, page: 1, per_page: 10)
      assert %{results: _, page: 1, per_page: 10, total: 1, total_pages: 1} = result
    end
  end

  describe "get_series/2" do
    test "scoped to org", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Test"})

      assert {:ok, found} = Content.get_series(org, series.id)
      assert found.id == series.id
    end

    test "returns error for other org's series", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Test"})

      other_org = insert(:organization)
      assert {:error, :not_found} = Content.get_series(other_org, series.id)
    end
  end

  describe "get_series_by_slug/2" do
    test "scoped to org", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Find Me"})

      assert {:ok, found} = Content.get_series_by_slug(org, series.slug)
      assert found.id == series.id
    end

    test "returns error for non-existent slug", %{org: org} do
      assert {:error, :not_found} = Content.get_series_by_slug(org, "nope")
    end

    test "excludes soft-deleted", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Deleted"})
      {:ok, _} = Content.delete_series(scope, series)

      assert {:error, :not_found} = Content.get_series_by_slug(org, series.slug)
    end
  end

  describe "update_series/3" do
    test "updates title, description, cover image", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Original"})

      assert {:ok, updated} =
               Content.update_series(scope, series, %{
                 title: "Updated",
                 description: "A description",
                 cover_image_url: "https://example.com/cover.jpg"
               })

      assert updated.title == "Updated"
      assert updated.description == "A description"
      assert updated.cover_image_url == "https://example.com/cover.jpg"
    end
  end

  describe "delete_series/2" do
    test "soft-deletes the series", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "To Delete"})
      {:ok, deleted} = Content.delete_series(scope, series)

      assert deleted.deleted_at != nil
      assert %{results: []} = Content.list_series(org)
    end

    test "also soft-deletes all seasons in the series", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "Season 1"})

      {:ok, _} = Content.delete_series(scope, series)

      reloaded = Repo.get!(Marquee.Content.Season, season.id)
      assert reloaded.deleted_at != nil
    end
  end

  ## -----------------------------------------------------------------------
  ## Season CRUD
  ## -----------------------------------------------------------------------

  describe "create_season/3" do
    test "creates with correct series association", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})

      assert {:ok, season} =
               Content.create_season(scope, series, %{title: "Season 1", season_number: 1})

      assert season.series_id == series.id
      assert season.organization_id == scope.organization.id
    end

    test "auto-assigns season_number if not provided", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})

      {:ok, s1} = Content.create_season(scope, series, %{title: "First"})
      {:ok, s2} = Content.create_season(scope, series, %{title: "Second"})

      assert s1.season_number == 1
      assert s2.season_number == 2
    end

    test "with explicit season_number uses it", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S5", season_number: 5})

      assert season.season_number == 5
    end

    test "defaults title to 'Season <n>' when no title given", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Breaking Code"})

      {:ok, s1} = Content.create_season(scope, series, %{})
      {:ok, s2} = Content.create_season(scope, series, %{})

      assert s1.title == "Season 1"
      assert s2.title == "Season 2"
    end

    test "defaults title when title is blank string", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Show Name"})

      {:ok, season} = Content.create_season(scope, series, %{"title" => "  "})

      assert season.title == "Season 1"
    end

    test "preserves an explicit title", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Show Name"})

      {:ok, season} = Content.create_season(scope, series, %{title: "Pilot Arc"})

      assert season.title == "Pilot Arc"
    end

    test "two different series can each have a 'Season 1' in the same org",
         %{scope: scope} do
      {:ok, series_a} = Content.create_series(scope, %{title: "Show A"})
      {:ok, series_b} = Content.create_series(scope, %{title: "Show B"})

      assert {:ok, season_a} = Content.create_season(scope, series_a, %{})
      assert {:ok, season_b} = Content.create_season(scope, series_b, %{})

      assert season_a.title == "Season 1"
      assert season_b.title == "Season 1"
      assert season_a.slug == season_b.slug
      assert season_a.series_id != season_b.series_id
    end

    test "two seasons in the SAME series cannot share a slug", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Show"})

      {:ok, _} = Content.create_season(scope, series, %{title: "Pilot"})

      assert {:error, :validation, changeset} =
               Content.create_season(scope, series, %{title: "Pilot", season_number: 2})

      # Ecto reports composite-constraint errors on the first field (:series_id).
      assert "has already been taken" in errors_on(changeset).series_id
    end
  end

  describe "list_seasons/3" do
    test "returns seasons ordered by season_number", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, s2} = Content.create_season(scope, series, %{title: "S2", season_number: 2})
      {:ok, s1} = Content.create_season(scope, series, %{title: "S1", season_number: 1})

      assert %{results: [first, second]} = Content.list_seasons(org, series)
      assert first.id == s1.id
      assert second.id == s2.id
    end

    test "excludes soft-deleted", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, active} = Content.create_season(scope, series, %{title: "Active", season_number: 1})
      {:ok, deleted} = Content.create_season(scope, series, %{title: "Deleted", season_number: 2})
      {:ok, _} = Content.delete_season(scope, deleted)

      assert %{results: [found]} = Content.list_seasons(org, series)
      assert found.id == active.id
    end

    test "scoped to org + series", %{org: org, scope: scope} do
      {:ok, series_a} = Content.create_series(scope, %{title: "Series A"})
      {:ok, series_b} = Content.create_series(scope, %{title: "Series B"})

      {:ok, _} =
        Content.create_season(scope, series_a, %{title: "Season Alpha", season_number: 1})

      {:ok, _} = Content.create_season(scope, series_b, %{title: "Season Beta", season_number: 1})

      assert %{results: results} = Content.list_seasons(org, series_a)
      assert length(results) == 1
    end
  end

  describe "count_seasons_for_series/1" do
    test "returns non-deleted season count", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, _} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      {:ok, _} = Content.create_season(scope, series, %{title: "S2", season_number: 2})

      assert Content.count_seasons_for_series(series) == 2
    end

    test "excludes soft-deleted seasons", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, s1} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      {:ok, _s2} = Content.create_season(scope, series, %{title: "S2", season_number: 2})
      {:ok, _} = Content.delete_season(scope, s1)

      assert Content.count_seasons_for_series(series) == 1
    end

    test "scoped to series + org", %{scope: scope} do
      {:ok, series_a} = Content.create_series(scope, %{title: "A"})
      {:ok, series_b} = Content.create_series(scope, %{title: "B"})
      {:ok, _} = Content.create_season(scope, series_a, %{title: "S1", season_number: 1})
      {:ok, _} = Content.create_season(scope, series_b, %{title: "S1", season_number: 1})
      {:ok, _} = Content.create_season(scope, series_b, %{title: "S2", season_number: 2})

      assert Content.count_seasons_for_series(series_a) == 1
      assert Content.count_seasons_for_series(series_b) == 2
    end
  end

  describe "next_season/2" do
    test "returns the next season by season_number", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, s1} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      {:ok, s2} = Content.create_season(scope, series, %{title: "S2", season_number: 2})

      next = Content.next_season(org, s1)
      assert next.id == s2.id
    end

    test "returns nil for the last season", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, s1} = Content.create_season(scope, series, %{title: "S1", season_number: 1})

      assert Content.next_season(org, s1) == nil
    end

    test "skips soft-deleted seasons", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, s1} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      {:ok, s2} = Content.create_season(scope, series, %{title: "S2", season_number: 2})
      {:ok, s3} = Content.create_season(scope, series, %{title: "S3", season_number: 3})
      {:ok, _} = Content.delete_season(scope, s2)

      next = Content.next_season(org, s1)
      assert next.id == s3.id
    end
  end

  describe "reorder_seasons/3" do
    test "updates season_numbers", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, s1} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      {:ok, s2} = Content.create_season(scope, series, %{title: "S2", season_number: 2})

      assert :ok = Content.reorder_seasons(scope, series, [s2.id, s1.id])

      assert %{results: [first, second]} = Content.list_seasons(org, series)
      assert first.id == s2.id
      assert first.season_number == 1
      assert second.id == s1.id
      assert second.season_number == 2
    end
  end

  ## -----------------------------------------------------------------------
  ## Episode management
  ## -----------------------------------------------------------------------

  describe "add_episode/3" do
    setup %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      video = insert(:video, organization: scope.organization)
      %{series: series, season: season, video: video}
    end

    test "creates episode linking season and video", %{scope: scope, season: season, video: video} do
      assert {:ok, episode} = Content.add_episode(scope, season, video)
      assert episode.season_id == season.id
      assert episode.video_id == video.id
    end

    test "auto-assigns episode_number", %{scope: scope, season: season, video: video} do
      {:ok, ep1} = Content.add_episode(scope, season, video)
      assert ep1.episode_number == 1

      video2 = insert(:video, organization: scope.organization)
      {:ok, ep2} = Content.add_episode(scope, season, video2)
      assert ep2.episode_number == 2
    end

    test "updates season.episode_count", %{scope: scope, season: season, video: video} do
      {:ok, _} = Content.add_episode(scope, season, video)

      reloaded = Repo.get!(Marquee.Content.Season, season.id)
      assert reloaded.episode_count == 1
    end

    test "with video already in season returns error", %{
      scope: scope,
      season: season,
      video: video
    } do
      {:ok, _} = Content.add_episode(scope, season, video)
      assert {:error, :already_exists} = Content.add_episode(scope, season, video)
    end

    test "preloads the video on the returned episode", %{
      scope: scope,
      season: season,
      video: video
    } do
      {:ok, episode} = Content.add_episode(scope, season, video)
      assert %Marquee.Content.Video{} = episode.video
      assert episode.video.id == video.id
    end
  end

  describe "remove_episode/3" do
    setup %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      video = insert(:video, organization: scope.organization)
      {:ok, _episode} = Content.add_episode(scope, season, video)
      %{series: series, season: season, video: video}
    end

    test "deletes the episode record (hard delete)", %{
      scope: scope,
      season: season,
      video: video
    } do
      assert :ok = Content.remove_episode(scope, season, video)

      assert Repo.get_by(Marquee.Content.Episode, season_id: season.id, video_id: video.id) ==
               nil
    end

    test "decrements season.episode_count", %{scope: scope, season: season, video: video} do
      Content.remove_episode(scope, season, video)

      reloaded = Repo.get!(Marquee.Content.Season, season.id)
      assert reloaded.episode_count == 0
    end

    test "does NOT delete the video", %{scope: scope, season: season, video: video} do
      Content.remove_episode(scope, season, video)

      assert Repo.get(Marquee.Content.Video, video.id) != nil
    end

    test "returns error for non-existent episode", %{scope: scope, season: season} do
      other_video = insert(:video, organization: scope.organization)
      assert {:error, :not_found} = Content.remove_episode(scope, season, other_video)
    end
  end

  describe "list_episodes/2" do
    test "returns episodes ordered by episode_number, preloads videos", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      v1 = insert(:video, organization: org)
      v2 = insert(:video, organization: org)
      {:ok, _} = Content.add_episode(scope, season, v2, %{episode_number: 2})
      {:ok, _} = Content.add_episode(scope, season, v1, %{episode_number: 1})

      episodes = Content.list_episodes(org, season)
      assert length(episodes) == 2
      assert Enum.at(episodes, 0).episode_number == 1
      assert Enum.at(episodes, 1).episode_number == 2
      assert %Marquee.Content.Video{} = Enum.at(episodes, 0).video
    end
  end

  describe "reorder_episodes/3" do
    test "updates episode_numbers", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      v1 = insert(:video, organization: org)
      v2 = insert(:video, organization: org)
      {:ok, _} = Content.add_episode(scope, season, v1)
      {:ok, _} = Content.add_episode(scope, season, v2)

      assert :ok = Content.reorder_episodes(scope, season, [v2.id, v1.id])

      episodes = Content.list_episodes(org, season)
      assert Enum.at(episodes, 0).video_id == v2.id
      assert Enum.at(episodes, 0).episode_number == 1
      assert Enum.at(episodes, 1).video_id == v1.id
      assert Enum.at(episodes, 1).episode_number == 2
    end
  end

  describe "next_episode/2" do
    test "returns the next episode in the season", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      v1 = insert(:video, organization: org)
      v2 = insert(:video, organization: org)
      {:ok, _} = Content.add_episode(scope, season, v1, %{episode_number: 1})
      {:ok, _} = Content.add_episode(scope, season, v2, %{episode_number: 2})

      next = Content.next_episode(org, v1)
      assert next.video_id == v2.id
    end

    test "returns nil for the last episode", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      v1 = insert(:video, organization: org)
      {:ok, _} = Content.add_episode(scope, season, v1, %{episode_number: 1})

      assert Content.next_episode(org, v1) == nil
    end

    test "returns nil for a standalone video", %{org: org} do
      standalone = insert(:video, organization: org)
      assert Content.next_episode(org, standalone) == nil
    end
  end

  ## -----------------------------------------------------------------------
  ## Episode context
  ## -----------------------------------------------------------------------

  describe "get_episode_context/2" do
    test "returns full context for an episode video", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      video = insert(:video, organization: org)
      {:ok, _} = Content.add_episode(scope, season, video, %{episode_number: 3})

      ctx = Content.get_episode_context(org, video)
      assert ctx.series.id == series.id
      assert ctx.season.id == season.id
      assert ctx.episode.video_id == video.id
      assert ctx.episode_number == 3
      assert ctx.season_number == 1
    end

    test "returns nil for standalone video", %{org: org} do
      standalone = insert(:video, organization: org)
      assert Content.get_episode_context(org, standalone) == nil
    end

    test "scoped to org", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      video = insert(:video, organization: scope.organization)
      {:ok, _} = Content.add_episode(scope, season, video)

      other_org = insert(:organization)
      assert Content.get_episode_context(other_org, video) == nil
    end
  end

  ## -----------------------------------------------------------------------
  ## Multi-tenant isolation
  ## -----------------------------------------------------------------------

  describe "multi-tenant isolation" do
    setup %{scope: scope} do
      other_org = insert(:organization)
      other_user = insert(:user)
      other_mem = insert(:membership, organization: other_org, user: other_user, role: :editor)
      other_scope = Scope.for_user(other_user) |> Scope.with_organization(other_org, other_mem)

      {:ok, series} = Content.create_series(scope, %{title: "Our Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      video = insert(:video, organization: scope.organization)
      {:ok, _} = Content.add_episode(scope, season, video)

      %{
        other_org: other_org,
        other_scope: other_scope,
        series: series,
        season: season,
        video: video
      }
    end

    test "series from org A not returned by list_series for org B", %{other_org: other_org} do
      assert %{results: []} = Content.list_series(other_org)
    end

    test "get_series with org B for a series on org A returns error", %{
      other_org: other_org,
      series: series
    } do
      assert {:error, :not_found} = Content.get_series(other_org, series.id)
    end

    test "season on org A not accessible from org B", %{other_org: other_org, season: season} do
      assert {:error, :not_found} = Content.get_season(other_org, season.id)
    end

    test "get_episode_context for org A video from org B returns nil", %{
      other_org: other_org,
      video: video
    } do
      assert Content.get_episode_context(other_org, video) == nil
    end
  end

  ## -----------------------------------------------------------------------
  ## Cascade behavior
  ## -----------------------------------------------------------------------

  describe "cascade behavior" do
    test "soft-deleting a series soft-deletes its seasons", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})

      {:ok, _} = Content.delete_series(scope, series)

      reloaded = Repo.get!(Marquee.Content.Season, season.id)
      assert reloaded.deleted_at != nil
    end

    test "soft-deleting a season does NOT delete its episodes' videos", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      video = insert(:video, organization: scope.organization)
      {:ok, _} = Content.add_episode(scope, season, video)

      {:ok, _} = Content.delete_season(scope, season)

      assert Repo.get(Marquee.Content.Video, video.id) != nil
    end
  end
end
