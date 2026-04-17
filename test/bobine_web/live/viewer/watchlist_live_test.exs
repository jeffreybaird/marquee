defmodule BobineWeb.Viewer.WatchlistLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /watchlist" do
    test "shows empty state when no items", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watchlist")
      assert html =~ ~s(data-test="sv-empty-state")
      assert html =~ "Your watchlist is empty"
      assert html =~ "Browse content"
    end

    test "shows watchlisted videos", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      video =
        insert(:video,
          organization: org,
          title: "Watchlisted Film",
          mux_status: "ready"
        )

      insert(:watchlist_item,
        organization: org,
        viewer: viewer,
        video: video
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watchlist")
      assert html =~ "Watchlisted Film"
      assert html =~ ~s(data-test="sv-watchlist-remove-#{video.id}")
    end

    test "remove from watchlist works", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      video =
        insert(:video,
          organization: org,
          title: "To Remove",
          mux_status: "ready"
        )

      insert(:watchlist_item,
        organization: org,
        viewer: viewer,
        video: video
      )

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/watchlist")
      assert html =~ "To Remove"

      html = render_click(view, "remove", %{"video-id" => video.id})
      refute html =~ "To Remove"
      assert html =~ "Your watchlist is empty"
    end
  end

  describe "GET /queue" do
    test "shows vertical sortable queue list with drag handles", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      video =
        insert(:video,
          organization: org,
          title: "Queue Video",
          mux_status: "ready",
          mux_playback_id: "pb_q1"
        )

      {:ok, _} = Bobine.Engagement.add_to_queue(org, viewer, video)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/queue")
      assert html =~ ~s(data-test="sv-queue-list")
      assert html =~ ~s(data-test="sv-queue-item-#{video.id}")
      assert html =~ ~s(data-test="queue-drag-handle")
      assert html =~ "Queue Video"
    end

    test "reorder_queue event updates order", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      v1 =
        insert(:video,
          organization: org,
          title: "First",
          mux_status: "ready",
          mux_playback_id: "pb_r1"
        )

      v2 =
        insert(:video,
          organization: org,
          title: "Second",
          mux_status: "ready",
          mux_playback_id: "pb_r2"
        )

      {:ok, _} = Bobine.Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Bobine.Engagement.add_to_queue(org, viewer, v2)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/queue")

      # Reorder: put v2 first
      render_hook(view, "reorder_queue", %{"ordered_ids" => [v2.id, v1.id]})

      # Verify reorder persisted
      %{results: items} = Bobine.Engagement.list_queue(org, viewer)
      assert [first | _] = items
      assert first.video_id == v2.id
    end

    test "remove from queue works on queue page", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      video =
        insert(:video,
          organization: org,
          title: "Remove Me",
          mux_status: "ready",
          mux_playback_id: "pb_rm"
        )

      {:ok, _} = Bobine.Engagement.add_to_queue(org, viewer, video)

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/queue")
      assert html =~ "Remove Me"

      html = render_click(view, "remove_from_queue", %{"video-id" => video.id})
      refute html =~ "Remove Me"
    end
  end

  describe "unauthenticated access" do
    test "redirects to /login", %{conn: _conn} do
      org = insert(:organization)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/watchlist")
      assert path in ["/login", "/subscribe"]
    end
  end
end
