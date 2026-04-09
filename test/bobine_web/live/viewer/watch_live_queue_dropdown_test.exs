defmodule BobineWeb.Viewer.WatchLiveQueueDropdownTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Bobine.Accounts.Scope
  alias Bobine.Content
  alias Bobine.Engagement

  defp build_series_with_episodes(org, opts) do
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

    {:ok, series} =
      Content.create_series(scope, %{title: Keyword.get(opts, :title, "Show")})

    {:ok, season} =
      Content.create_season(scope, series, %{title: "S1", season_number: 1})

    episode_count = Keyword.get(opts, :episodes, 3)

    episodes =
      for i <- 1..episode_count do
        v =
          insert(:video,
            organization: org,
            title: "S1E#{i}",
            mux_status: "ready",
            mux_playback_id: "pb_s1e#{i}",
            visibility: "subscribers_only",
            duration: 1800.0
          )

        {:ok, _} = Content.add_episode(scope, season, v, %{episode_number: i})
        v
      end

    %{scope: scope, series: series, season: season, videos: episodes}
  end

  ## -----------------------------------------------------------------------
  ## Dropdown UI
  ## -----------------------------------------------------------------------

  describe "season add-to-queue dropdown" do
    test "season header renders the dropdown trigger", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      %{videos: [v1 | _]} = build_series_with_episodes(org, episodes: 2)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{v1.id}")
      assert html =~ ~s(data-test="season-queue-btn")
    end

    test "clicking the trigger reveals the dropdown options", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      %{videos: [v1 | _], season: season} = build_series_with_episodes(org, episodes: 2)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{v1.id}")

      html =
        view
        |> element(~s([data-test="season-queue-btn"]))
        |> render_click()

      assert html =~ ~s(data-test="queue-dropdown-season-#{season.id}")
      assert html =~ ~s(data-test="queue-add-end-#{season.id}")
      assert html =~ ~s(data-test="queue-add-beginning-#{season.id}")
    end

    test "clicking again closes the dropdown", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      %{videos: [v1 | _], season: season} = build_series_with_episodes(org, episodes: 2)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{v1.id}")
      view |> element(~s([data-test="season-queue-btn"])) |> render_click()
      html = view |> element(~s([data-test="season-queue-btn"])) |> render_click()

      refute html =~ ~s(data-test="queue-dropdown-season-#{season.id}")
    end
  end

  ## -----------------------------------------------------------------------
  ## Add season — no progress (no confirmation)
  ## -----------------------------------------------------------------------

  describe "add season with no progress" do
    test "adds all episodes to end without confirmation", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      %{videos: [v1 | _] = vs, season: season} = build_series_with_episodes(org, episodes: 3)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{v1.id}")

      view |> element(~s([data-test="season-queue-btn"])) |> render_click()

      view
      |> element(~s([data-test="queue-add-end-#{season.id}"]))
      |> render_click()

      queue = Engagement.list_queue(org, viewer)
      assert length(queue) == 3
      assert Enum.map(queue, & &1.video_id) == Enum.map(vs, & &1.id)
    end

    test "adds all episodes to beginning when 'beginning' chosen", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      existing = insert(:video, organization: org, title: "Existing")
      {:ok, _} = Engagement.add_to_queue(org, viewer, existing)

      %{videos: [v1, v2, v3], season: season} = build_series_with_episodes(org, episodes: 3)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{v1.id}")
      view |> element(~s([data-test="season-queue-btn"])) |> render_click()

      view
      |> element(~s([data-test="queue-add-beginning-#{season.id}"]))
      |> render_click()

      queue_ids = Engagement.list_queue(org, viewer) |> Enum.map(& &1.video_id)
      assert queue_ids == [v1.id, v2.id, v3.id, existing.id]
    end
  end

  ## -----------------------------------------------------------------------
  ## Add season — with progress triggers confirmation dialog
  ## -----------------------------------------------------------------------

  describe "add season with existing progress" do
    test "shows the confirmation dialog when viewer has progress", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      %{videos: [v1 | _], season: season} = build_series_with_episodes(org, episodes: 3)

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: v1,
        position: 100.0,
        duration: 1800.0,
        completed: false
      )

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{v1.id}")
      view |> element(~s([data-test="season-queue-btn"])) |> render_click()

      html =
        view
        |> element(~s([data-test="queue-add-end-#{season.id}"]))
        |> render_click()

      assert html =~ ~s(data-test="queue-season-dialog")
      assert html =~ ~s(data-test="confirm-add-all")
      assert html =~ ~s(data-test="confirm-add-unwatched")
      assert html =~ ~s(data-test="confirm-cancel")

      # Nothing should be queued yet — confirmation pending
      assert Engagement.list_queue(org, viewer) == []
    end

    test "'all episodes' adds every episode", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      %{videos: [v1, v2, v3], season: season} = build_series_with_episodes(org, episodes: 3)

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: v1,
        position: 100.0,
        duration: 1800.0,
        completed: false
      )

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{v1.id}")
      view |> element(~s([data-test="season-queue-btn"])) |> render_click()
      view |> element(~s([data-test="queue-add-end-#{season.id}"])) |> render_click()
      view |> element(~s([data-test="confirm-add-all"])) |> render_click()

      queue_ids = Engagement.list_queue(org, viewer) |> Enum.map(& &1.video_id)
      assert v1.id in queue_ids
      assert v2.id in queue_ids
      assert v3.id in queue_ids
    end

    test "'only unwatched' filters completed episodes", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      %{videos: [v1, v2, v3], season: season} = build_series_with_episodes(org, episodes: 3)

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: v1,
        position: 1800.0,
        duration: 1800.0,
        completed: true
      )

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{v2.id}")
      view |> element(~s([data-test="season-queue-btn"])) |> render_click()
      view |> element(~s([data-test="queue-add-end-#{season.id}"])) |> render_click()
      view |> element(~s([data-test="confirm-add-unwatched"])) |> render_click()

      queue_ids = Engagement.list_queue(org, viewer) |> Enum.map(& &1.video_id)
      refute v1.id in queue_ids
      assert v2.id in queue_ids
      assert v3.id in queue_ids
    end

    test "'cancel' closes the dialog without queueing", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      %{videos: [v1 | _], season: season} = build_series_with_episodes(org, episodes: 2)

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: v1,
        position: 100.0,
        duration: 1800.0,
        completed: false
      )

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{v1.id}")
      view |> element(~s([data-test="season-queue-btn"])) |> render_click()
      view |> element(~s([data-test="queue-add-end-#{season.id}"])) |> render_click()

      html =
        view
        |> element(~s([data-test="confirm-cancel"]))
        |> render_click()

      refute html =~ ~s(data-test="queue-season-dialog")
      assert Engagement.list_queue(org, viewer) == []
    end
  end
end
