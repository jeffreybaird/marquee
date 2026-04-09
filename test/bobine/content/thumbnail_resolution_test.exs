defmodule Bobine.Content.ThumbnailResolutionTest do
  use Bobine.DataCase, async: false

  alias Bobine.Accounts.Scope
  alias Bobine.Cache
  alias Bobine.Content

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

    %{org: org, scope: scope}
  end

  ## -----------------------------------------------------------------------
  ## resolve_series_thumbnail/1
  ## -----------------------------------------------------------------------

  describe "resolve_series_thumbnail/1" do
    test "returns the series cover_image_url when set", %{scope: scope} do
      {:ok, series} =
        Content.create_series(scope, %{
          title: "Cover Series",
          cover_image_url: "https://example.com/cover.jpg"
        })

      assert Content.resolve_series_thumbnail(series) == "https://example.com/cover.jpg"
    end

    test "falls back to the latest season's thumbnail when cover is missing", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})

      {:ok, _s1} =
        Content.create_season(scope, series, %{title: "S1", cover_image_url: "season1.jpg"})

      {:ok, _s2} =
        Content.create_season(scope, series, %{title: "S2", cover_image_url: "season2.jpg"})

      assert Content.resolve_series_thumbnail(series) == "season2.jpg"
    end

    test "latest season is the one with the highest season_number", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})

      {:ok, _s2} =
        Content.create_season(scope, series, %{
          title: "S2",
          season_number: 2,
          cover_image_url: "second.jpg"
        })

      {:ok, _s5} =
        Content.create_season(scope, series, %{
          title: "S5",
          season_number: 5,
          cover_image_url: "fifth.jpg"
        })

      {:ok, _s3} =
        Content.create_season(scope, series, %{
          title: "S3",
          season_number: 3,
          cover_image_url: "third.jpg"
        })

      assert Content.resolve_series_thumbnail(series) == "fifth.jpg"
    end

    test "falls through season → first episode Mux thumbnail when no covers set",
         %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1"})

      video =
        insert(:video, organization: org, mux_playback_id: "first_playback", mux_status: "ready")

      {:ok, _ep} = Content.add_episode(scope, season, video)

      url = Content.resolve_series_thumbnail(series)
      assert url =~ "first_playback"
      assert url =~ "image.mux.com"
    end

    test "returns placeholder when series has no seasons", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Empty Series"})

      assert Content.resolve_series_thumbnail(series) == Content.placeholder_thumbnail()
    end

    test "ignores soft-deleted seasons when finding latest", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})

      {:ok, _s1} =
        Content.create_season(scope, series, %{
          title: "S1",
          season_number: 1,
          cover_image_url: "alive.jpg"
        })

      {:ok, s2} =
        Content.create_season(scope, series, %{
          title: "S2",
          season_number: 2,
          cover_image_url: "dead.jpg"
        })

      {:ok, _} = Content.delete_season(scope, s2)

      assert Content.resolve_series_thumbnail(series) == "alive.jpg"
    end
  end

  ## -----------------------------------------------------------------------
  ## resolve_season_thumbnail/1
  ## -----------------------------------------------------------------------

  describe "resolve_season_thumbnail/1" do
    test "returns season cover_image_url when set", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})

      {:ok, season} =
        Content.create_season(scope, series, %{
          title: "S1",
          cover_image_url: "https://example.com/season.jpg"
        })

      assert Content.resolve_season_thumbnail(season) == "https://example.com/season.jpg"
    end

    test "falls back to first episode Mux thumbnail when no cover", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1"})

      v1 = insert(:video, organization: org, mux_playback_id: "ep1_playback")
      v2 = insert(:video, organization: org, mux_playback_id: "ep2_playback")

      {:ok, _} = Content.add_episode(scope, season, v1, %{episode_number: 1})
      {:ok, _} = Content.add_episode(scope, season, v2, %{episode_number: 2})

      url = Content.resolve_season_thumbnail(season)
      assert url =~ "ep1_playback"
      refute url =~ "ep2_playback"
    end

    test "first episode is the one with the lowest episode_number", %{org: org, scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1"})

      v_high = insert(:video, organization: org, mux_playback_id: "high_pb")
      v_low = insert(:video, organization: org, mux_playback_id: "low_pb")

      {:ok, _} = Content.add_episode(scope, season, v_high, %{episode_number: 5})
      {:ok, _} = Content.add_episode(scope, season, v_low, %{episode_number: 1})

      url = Content.resolve_season_thumbnail(season)
      assert url =~ "low_pb"
    end

    test "returns placeholder when season has no episodes", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1"})

      assert Content.resolve_season_thumbnail(season) == Content.placeholder_thumbnail()
    end
  end

  ## -----------------------------------------------------------------------
  ## Cache behavior
  ## -----------------------------------------------------------------------

  describe "thumbnail caching" do
    setup do
      Cache.delete_by_prefix("series_thumb:")
      Cache.delete_by_prefix("season_thumb:")
      :ok
    end

    test "resolve_series_thumbnail_cached/1 matches uncached output", %{scope: scope} do
      {:ok, series} =
        Content.create_series(scope, %{title: "Cached", cover_image_url: "cover.jpg"})

      assert Content.resolve_series_thumbnail_cached(series) ==
               Content.resolve_series_thumbnail(series)
    end

    test "cache is invalidated when a series is updated", %{scope: scope} do
      {:ok, series} =
        Content.create_series(scope, %{title: "Toggle", cover_image_url: "v1.jpg"})

      assert Content.resolve_series_thumbnail_cached(series) == "v1.jpg"

      {:ok, updated} =
        Content.update_series(scope, series, %{cover_image_url: "v2.jpg"})

      assert Content.resolve_series_thumbnail_cached(updated) == "v2.jpg"
    end

    test "cache is invalidated when a season is added", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Will Get Season"})

      # Prime the cache — series has no seasons → placeholder
      assert Content.resolve_series_thumbnail_cached(series) == Content.placeholder_thumbnail()

      {:ok, _season} =
        Content.create_season(scope, series, %{title: "S1", cover_image_url: "s1.jpg"})

      # Cache should have been invalidated by create_season
      assert Content.resolve_series_thumbnail_cached(series) == "s1.jpg"
    end
  end

  ## -----------------------------------------------------------------------
  ## Multi-tenant
  ## -----------------------------------------------------------------------

  describe "multi-tenant isolation" do
    test "thumbnail resolution does not cross orgs", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "My Series"})

      # Create a foreign org with its own series + season
      other_org = insert(:organization)
      other_user = insert(:user)
      other_mem = insert(:membership, organization: other_org, user: other_user, role: :editor)
      other_scope = Scope.for_user(other_user) |> Scope.with_organization(other_org, other_mem)

      {:ok, other_series} = Content.create_series(other_scope, %{title: "Other Series"})

      {:ok, _other_season} =
        Content.create_season(other_scope, other_series, %{
          title: "Foreign",
          cover_image_url: "foreign.jpg"
        })

      # Our series has no seasons → must return placeholder, not the foreign cover
      assert Content.resolve_series_thumbnail(series) == Content.placeholder_thumbnail()
    end
  end
end
