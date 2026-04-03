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
