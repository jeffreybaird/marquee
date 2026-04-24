defmodule BobineWeb.Components.ContentCardTest do
  use Bobine.DataCase, async: false

  import Phoenix.LiveViewTest

  alias Bobine.Accounts.Scope
  alias Bobine.Cache
  alias Bobine.Content
  alias BobineWeb.Components.ViewerComponents

  setup do
    Cache.delete_by_prefix("series_thumb:")
    Cache.delete_by_prefix("season_thumb:")

    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

    %{org: org, scope: scope}
  end

  ## -----------------------------------------------------------------------
  ## content_card (video)
  ## -----------------------------------------------------------------------

  describe "content_card/1 (video)" do
    test "renders video title and thumbnail link", %{org: org} do
      video =
        insert(:video,
          organization: org,
          title: "Sample Video",
          mux_playback_id: "vid_pb",
          duration: 120.0
        )

      html = render_component(&ViewerComponents.content_card/1, %{video: video})

      assert html =~ "Sample Video"
      assert html =~ ~s(data-test="sv-card-#{video.id}")
      assert html =~ "/watch/#{video.id}"
      assert html =~ "vid_pb"
    end

    test "uses portrait thumbnail URL when aspect: :portrait and portrait_thumbnail_url set",
         %{org: org} do
      video =
        insert(:video,
          organization: org,
          portrait_thumbnail_url: "https://example.com/portrait.jpg",
          landscape_thumbnail_url: "https://example.com/landscape.jpg",
          mux_playback_id: "pb_fallback"
        )

      html =
        render_component(&ViewerComponents.content_card/1, %{video: video, aspect: :portrait})

      assert html =~ "https://example.com/portrait.jpg"
      refute html =~ "https://example.com/landscape.jpg"
    end

    test "uses landscape thumbnail URL when aspect: :landscape and landscape_thumbnail_url set",
         %{org: org} do
      video =
        insert(:video,
          organization: org,
          portrait_thumbnail_url: "https://example.com/portrait.jpg",
          landscape_thumbnail_url: "https://example.com/landscape.jpg",
          mux_playback_id: "pb_fallback"
        )

      html =
        render_component(&ViewerComponents.content_card/1, %{video: video, aspect: :landscape})

      assert html =~ "https://example.com/landscape.jpg"
      refute html =~ "https://example.com/portrait.jpg"
    end

    test "defaults to landscape thumbnail when no aspect specified", %{org: org} do
      video =
        insert(:video,
          organization: org,
          portrait_thumbnail_url: "https://example.com/portrait.jpg",
          landscape_thumbnail_url: "https://example.com/landscape.jpg",
          mux_playback_id: "pb_fallback"
        )

      html = render_component(&ViewerComponents.content_card/1, %{video: video})

      assert html =~ "https://example.com/landscape.jpg"
      refute html =~ "https://example.com/portrait.jpg"
    end
  end

  ## -----------------------------------------------------------------------
  ## series_card
  ## -----------------------------------------------------------------------

  describe "series_card/1" do
    test "renders title, season count, and links to /series/:slug", %{scope: scope} do
      {:ok, series} =
        Content.create_series(scope, %{
          title: "My Show",
          cover_image_url: "https://example.com/cover.jpg"
        })

      {:ok, _s1} = Content.create_season(scope, series, %{title: "S1"})
      {:ok, _s2} = Content.create_season(scope, series, %{title: "S2"})

      Cache.delete_by_prefix("series_thumb:")

      html = render_component(&ViewerComponents.series_card/1, %{series: series})

      assert html =~ "My Show"
      assert html =~ "2 Seasons"
      assert html =~ "/series/#{series.slug}"
      assert html =~ ~s(data-test="series-card-#{series.id}")
      assert html =~ "https://example.com/cover.jpg"
    end

    test "single season renders 'Season' singular", %{scope: scope} do
      {:ok, series} =
        Content.create_series(scope, %{title: "Solo", cover_image_url: "x.jpg"})

      {:ok, _s1} = Content.create_season(scope, series, %{title: "S1"})

      Cache.delete_by_prefix("series_thumb:")

      html = render_component(&ViewerComponents.series_card/1, %{series: series})

      assert html =~ "1 Season"
      refute html =~ "1 Seasons"
    end

    test "renders New Season badge when flag is true", %{scope: scope} do
      {:ok, series} =
        Content.create_series(scope, %{
          title: "Hot",
          cover_image_url: "x.jpg",
          new_season: true
        })

      html = render_component(&ViewerComponents.series_card/1, %{series: series})

      assert html =~ "New Season"
      assert html =~ ~s(data-test="new-season-badge-#{series.id}")
    end

    test "no badge when flag is false", %{scope: scope} do
      {:ok, series} =
        Content.create_series(scope, %{title: "Cold", cover_image_url: "x.jpg"})

      html = render_component(&ViewerComponents.series_card/1, %{series: series})

      refute html =~ ~s(data-test="new-season-badge-#{series.id}")
    end

    test "no badge when flag is set but expiry is in the past", %{scope: scope} do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {:ok, series} =
        Content.create_series(scope, %{
          title: "Stale",
          cover_image_url: "x.jpg",
          new_season: true,
          new_season_expires_at: past
        })

      html = render_component(&ViewerComponents.series_card/1, %{series: series})

      refute html =~ ~s(data-test="new-season-badge-#{series.id}")
    end

    test "badge shown when flag is set with future expiry", %{scope: scope} do
      future = DateTime.utc_now() |> DateTime.add(7 * 86_400, :second)

      {:ok, series} =
        Content.create_series(scope, %{
          title: "Fresh",
          cover_image_url: "x.jpg",
          new_season: true,
          new_season_expires_at: future
        })

      html = render_component(&ViewerComponents.series_card/1, %{series: series})

      assert html =~ ~s(data-test="new-season-badge-#{series.id}")
    end

    test "uses sv-card classes for visual parity with video card", %{scope: scope} do
      {:ok, series} =
        Content.create_series(scope, %{title: "Same Shape", cover_image_url: "x.jpg"})

      html = render_component(&ViewerComponents.series_card/1, %{series: series})

      assert html =~ "sv-card-container"
      assert html =~ "sv-card-thumb"
      assert html =~ "sv-card-info"
      assert html =~ "sv-card-title"
    end
  end

  ## -----------------------------------------------------------------------
  ## season_card
  ## -----------------------------------------------------------------------

  describe "season_card/1" do
    test "renders title, episode count, and links to series page", %{scope: scope} do
      {:ok, series} =
        Content.create_series(scope, %{title: "Show", cover_image_url: "x.jpg"})

      {:ok, season} =
        Content.create_season(scope, series, %{
          title: "Season 1",
          season_number: 1,
          cover_image_url: "season.jpg"
        })

      season =
        season
        |> Bobine.Repo.preload(:series)
        |> Map.put(:episode_count, 8)

      html = render_component(&ViewerComponents.season_card/1, %{season: season})

      assert html =~ "Season 1"
      assert html =~ "8 Episodes"
      assert html =~ "/series/#{series.slug}/season/1"
      assert html =~ ~s(data-test="season-card-#{season.id}")
    end

    test "single episode uses singular wording", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Show", cover_image_url: "x.jpg"})

      {:ok, season} =
        Content.create_season(scope, series, %{
          title: "Pilot",
          season_number: 1,
          cover_image_url: "p.jpg"
        })

      season =
        season
        |> Bobine.Repo.preload(:series)
        |> Map.put(:episode_count, 1)

      html = render_component(&ViewerComponents.season_card/1, %{season: season})

      assert html =~ "1 Episode"
      refute html =~ "1 Episodes"
    end
  end

  ## -----------------------------------------------------------------------
  ## content_item_card dispatcher
  ## -----------------------------------------------------------------------

  describe "content_item_card/1" do
    test "dispatches a Video to a video card", %{org: org} do
      video =
        insert(:video, organization: org, title: "Disp Video", mux_playback_id: "p")

      html = render_component(&ViewerComponents.content_item_card/1, %{item: video})

      assert html =~ ~s(data-test="sv-card-#{video.id}")
      assert html =~ "Disp Video"
    end

    test "dispatches a Series to a series card", %{scope: scope} do
      {:ok, series} =
        Content.create_series(scope, %{title: "Disp Series", cover_image_url: "x.jpg"})

      html = render_component(&ViewerComponents.content_item_card/1, %{item: series})

      assert html =~ ~s(data-test="series-card-#{series.id}")
      assert html =~ "Disp Series"
    end

    test "dispatches a Season to a season card", %{scope: scope} do
      {:ok, series} =
        Content.create_series(scope, %{title: "Show", cover_image_url: "x.jpg"})

      {:ok, season} =
        Content.create_season(scope, series, %{
          title: "Disp Season",
          cover_image_url: "s.jpg"
        })

      season = Bobine.Repo.preload(season, :series)

      html = render_component(&ViewerComponents.content_item_card/1, %{item: season})

      assert html =~ ~s(data-test="season-card-#{season.id}")
      assert html =~ "Disp Season"
    end

    test "unwraps CollectionItem with video and dispatches to video card", %{org: org} do
      video =
        insert(:video, organization: org, title: "Wrapped Video", mux_playback_id: "wp")

      collection = insert(:collection, organization: org)

      ci =
        insert(:collection_item,
          organization: org,
          collection: collection,
          video: video,
          item_type: :video
        )

      html = render_component(&ViewerComponents.content_item_card/1, %{item: ci})

      assert html =~ ~s(data-test="sv-card-#{video.id}")
      assert html =~ "Wrapped Video"
    end

    test "unwraps CollectionItem with series and dispatches to series card", %{
      org: org,
      scope: scope
    } do
      {:ok, series} =
        Content.create_series(scope, %{title: "Wrapped Series", cover_image_url: "x.jpg"})

      collection = insert(:collection, organization: org)

      ci =
        insert(:collection_item,
          organization: org,
          collection: collection,
          video: nil,
          series: series,
          item_type: :series
        )

      html = render_component(&ViewerComponents.content_item_card/1, %{item: ci})

      assert html =~ ~s(data-test="series-card-#{series.id}")
      assert html =~ "Wrapped Series"
    end

    test "unwraps CollectionItem with season and dispatches to season card", %{
      org: org,
      scope: scope
    } do
      {:ok, series} =
        Content.create_series(scope, %{title: "Show", cover_image_url: "x.jpg"})

      {:ok, season} =
        Content.create_season(scope, series, %{
          title: "Wrapped Season",
          cover_image_url: "s.jpg"
        })

      season = Bobine.Repo.preload(season, :series)
      collection = insert(:collection, organization: org)

      ci =
        insert(:collection_item,
          organization: org,
          collection: collection,
          video: nil,
          season: season,
          item_type: :season
        )

      html = render_component(&ViewerComponents.content_item_card/1, %{item: ci})

      assert html =~ ~s(data-test="season-card-#{season.id}")
      assert html =~ "Wrapped Season"
    end
  end
end
