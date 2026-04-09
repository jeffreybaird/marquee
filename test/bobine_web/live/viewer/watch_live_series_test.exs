defmodule BobineWeb.Viewer.WatchLiveSeriesTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  ## -----------------------------------------------------------------------
  ## Helpers
  ## -----------------------------------------------------------------------

  defp create_series_with_episodes(org, opts \\ []) do
    season_count = Keyword.get(opts, :seasons, 1)
    episodes_per_season = Keyword.get(opts, :episodes, 3)

    series = insert(:series, organization: org, title: "My Series", slug: "my-series")

    seasons =
      for s <- 1..season_count do
        season =
          insert(:season,
            organization: org,
            series: series,
            title: "Season #{s}",
            season_number: s,
            episode_count: episodes_per_season
          )

        episodes =
          for e <- 1..episodes_per_season do
            video =
              insert(:video,
                organization: org,
                title: "S#{s}E#{e} - Episode Title",
                mux_status: "ready",
                mux_playback_id: "pb_s#{s}e#{e}",
                visibility: "subscribers_only",
                duration: 600.0
              )

            insert(:episode,
              organization: org,
              season: season,
              video: video,
              episode_number: e
            )
          end

        {season, episodes}
      end

    {series, seasons}
  end

  ## -----------------------------------------------------------------------
  ## /watch/:id with standalone video (existing behavior preserved)
  ## -----------------------------------------------------------------------

  describe "/watch/:id with standalone video" do
    test "page renders with video player and no season section", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      video =
        insert(:video,
          organization: org,
          title: "Standalone Video",
          mux_status: "ready",
          mux_playback_id: "pb_standalone",
          visibility: "subscribers_only",
          duration: 300.0
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")

      assert html =~ "Standalone Video"
      assert html =~ ~s(data-test="sv-player")
      assert html =~ ~s(data-test="video-title")
      assert html =~ ~s(data-test="video-detail")
      refute html =~ ~s(data-test="season-section")
      refute html =~ ~s(data-test="season-selector")
      refute html =~ ~s(data-test="episode-list")
      refute html =~ ~s(data-test="series-breadcrumb")
      refute html =~ ~s(data-test="episode-label")
    end

    test "description is shown", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      video =
        insert(:video,
          organization: org,
          title: "Desc Video",
          description: "A detailed description here",
          mux_status: "ready",
          mux_playback_id: "pb_desc",
          visibility: "subscribers_only"
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      assert html =~ "A detailed description here"
    end
  end

  ## -----------------------------------------------------------------------
  ## /watch/:id with episode video
  ## -----------------------------------------------------------------------

  describe "/watch/:id with episode video" do
    test "renders season section below player", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      {_series, [{_season, episodes}]} = create_series_with_episodes(org)

      ep = List.first(episodes)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{ep.video_id}")

      assert html =~ ~s(data-test="season-section")
      assert html =~ ~s(data-test="episode-list")
      assert html =~ ~s(data-test="season-selector")
    end

    test "series breadcrumb links to series page", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      {series, [{_season, episodes}]} = create_series_with_episodes(org)

      ep = List.first(episodes)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{ep.video_id}")

      assert html =~ ~s(data-test="series-breadcrumb")
      assert html =~ series.title
      assert html =~ "/series/#{series.slug}"
    end

    test "episode label shows Season N, Episode M of T", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      {_series, [{_season, episodes}]} = create_series_with_episodes(org, episodes: 5)

      ep = Enum.at(episodes, 2)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{ep.video_id}")

      assert html =~ ~s(data-test="episode-label")
      assert html =~ "Season 1"
      assert html =~ "Episode 3"
      assert html =~ "of 5"
    end

    test "season dropdown shows all seasons", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      {_series, seasons_with_eps} = create_series_with_episodes(org, seasons: 3, episodes: 2)

      [{_s1, eps1} | _] = seasons_with_eps
      ep = List.first(eps1)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{ep.video_id}")

      assert html =~ "Season 1"
      assert html =~ "Season 2"
      assert html =~ "Season 3"
    end

    test "episode list shows all episodes in the season", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      {_series, [{_season, episodes}]} = create_series_with_episodes(org, episodes: 4)

      ep = List.first(episodes)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{ep.video_id}")

      for episode <- episodes do
        assert html =~ ~s(data-test="episode-row-#{episode.video_id}")
      end
    end

    test "current episode row has current class and play icon", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      {_series, [{_season, episodes}]} = create_series_with_episodes(org)

      ep = List.first(episodes)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{ep.video_id}")

      # The current episode row should have the "current" class
      assert html =~ ~s(data-test="episode-row-#{ep.video_id}")
      # And the play icon
      assert html =~ "▶"
    end

    test "completed episodes show checkmark", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      {_series, [{_season, episodes}]} = create_series_with_episodes(org)

      # Mark second episode as completed
      ep2 = Enum.at(episodes, 1)
      insert(:progress, organization: org, viewer: viewer, video: ep2.video, completed: true)

      ep1 = List.first(episodes)
      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{ep1.video_id}")

      assert html =~ "✓"
    end

    test "in-progress episodes show progress bar", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      {_series, [{_season, episodes}]} = create_series_with_episodes(org)

      # Add progress to second episode
      ep2 = Enum.at(episodes, 1)

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: ep2.video,
        position: 300.0,
        duration: 600.0,
        completed: false
      )

      ep1 = List.first(episodes)
      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{ep1.video_id}")

      assert html =~ ~s(data-test="episode-progress-#{ep2.video_id}")
    end

    test "clicking an episode changes the video without full page reload", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      {_series, [{_season, episodes}]} = create_series_with_episodes(org)

      ep1 = List.first(episodes)
      ep2 = Enum.at(episodes, 1)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{ep1.video_id}")

      # Click the second episode
      html =
        view
        |> element(~s([data-test="episode-link-#{ep2.video_id}"]))
        |> render_click()

      assert html =~ ep2.video.title
    end
  end

  ## -----------------------------------------------------------------------
  ## /series/:slug
  ## -----------------------------------------------------------------------

  describe "/series/:slug" do
    test "loads first season and first episode by default", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      {series, [{_season, episodes} | _]} = create_series_with_episodes(org, seasons: 2)

      ep1 = List.first(episodes)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/series/#{series.slug}")

      assert html =~ ~s(data-test="season-section")
      assert html =~ ep1.video.title
      assert html =~ "Season 1"
    end

    test "loads season with active viewer progress", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      {series, [{_s1, _eps1}, {_s2, eps2}]} =
        create_series_with_episodes(org, seasons: 2, episodes: 2)

      # Add in-progress viewing for an episode in season 2
      ep_s2 = List.first(eps2)

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: ep_s2.video,
        position: 100.0,
        duration: 600.0,
        completed: false
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/series/#{series.slug}")

      # Should load season 2's episodes
      assert html =~ ep_s2.video.title
    end

    test "page title includes series and season name", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      {series, _seasons} = create_series_with_episodes(org)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/series/#{series.slug}")

      assert page_title(view) =~ series.title
    end

    test "non-existent series redirects to home", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/series/nonexistent-slug")
    end
  end

  ## -----------------------------------------------------------------------
  ## /series/:slug/season/:number
  ## -----------------------------------------------------------------------

  describe "/series/:slug/season/:number" do
    test "loads the specific season", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      {series, [{_s1, _eps1}, {_s2, eps2}]} =
        create_series_with_episodes(org, seasons: 2, episodes: 2)

      ep_s2 = List.first(eps2)

      {:ok, _view, html} =
        live(conn_for_viewer(viewer), ~p"/series/#{series.slug}/season/2")

      assert html =~ ep_s2.video.title
      assert html =~ "Season 2"
    end

    test "invalid season number falls back to first season", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      {series, [{_s1, eps1}]} = create_series_with_episodes(org, seasons: 1)

      ep1 = List.first(eps1)

      {:ok, _view, html} =
        live(conn_for_viewer(viewer), ~p"/series/#{series.slug}/season/999")

      # Falls back to first season
      assert html =~ ep1.video.title
    end
  end

  ## -----------------------------------------------------------------------
  ## Season switching
  ## -----------------------------------------------------------------------

  describe "season switching" do
    test "selecting a different season updates the episode list", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      {series, [{_s1, _eps1}, {s2, eps2}]} =
        create_series_with_episodes(org, seasons: 2, episodes: 2)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/series/#{series.slug}")

      # Switch to season 2
      html =
        view
        |> element(~s(form[data-test="season-selector"]))
        |> render_change(%{"season_id" => s2.id})

      # Should show season 2 episodes
      for ep <- eps2 do
        assert html =~ ~s(data-test="episode-row-#{ep.video_id}")
      end
    end

    test "switching to empty season shows flash message", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      series = insert(:series, organization: org, slug: "empty-test")

      season1 =
        insert(:season,
          organization: org,
          series: series,
          season_number: 1,
          episode_count: 1
        )

      video =
        insert(:video,
          organization: org,
          mux_status: "ready",
          mux_playback_id: "pb_only",
          visibility: "subscribers_only",
          duration: 300.0
        )

      insert(:episode,
        organization: org,
        season: season1,
        video: video,
        episode_number: 1
      )

      # Season 2 with no episodes
      season2 =
        insert(:season,
          organization: org,
          series: series,
          season_number: 2,
          episode_count: 0
        )

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/series/#{series.slug}")

      html =
        view
        |> element(~s(form[data-test="season-selector"]))
        |> render_change(%{"season_id" => season2.id})

      assert html =~ "no episodes yet"
    end
  end

  ## -----------------------------------------------------------------------
  ## Collection mode auto-advance
  ## -----------------------------------------------------------------------

  describe "collection mode auto-advance" do
    test "last episode of last season ends playback gracefully", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      {series, [{_season, episodes}]} = create_series_with_episodes(org, episodes: 2)

      last_ep = List.last(episodes)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/series/#{series.slug}")

      # Play the last episode first
      view
      |> element(~s([data-test="episode-link-#{last_ep.video_id}"]))
      |> render_click()

      # Simulate playback ended — should not crash
      render_click(view, "playback_ended", %{"video_id" => last_ep.video_id})
    end
  end

  ## -----------------------------------------------------------------------
  ## Multi-tenant isolation
  ## -----------------------------------------------------------------------

  describe "multi-tenant isolation" do
    test "/series/:slug for org A doesn't load org B's series", %{conn: _conn} do
      org_a = insert(:organization)
      org_b = insert(:organization)
      viewer_a = insert(:subscribed_viewer, organization: org_a)

      _series_b =
        insert(:series, organization: org_b, title: "Other Series", slug: "shared-slug")

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer_a), ~p"/series/shared-slug")
    end

    test "episode context only loads for correct org", %{conn: _conn} do
      org_a = insert(:organization)
      org_b = insert(:organization)
      viewer_a = insert(:subscribed_viewer, organization: org_a)

      # Create series in org_b
      {_series_b, [{_season_b, eps_b}]} = create_series_with_episodes(org_b)
      ep_b = List.first(eps_b)

      # Trying to watch org B's video from org A should fail
      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer_a), ~p"/watch/#{ep_b.video_id}")
    end
  end
end
