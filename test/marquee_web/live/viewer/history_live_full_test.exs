defmodule MarqueeWeb.Viewer.HistoryLiveFullTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    org = insert(:organization)
    viewer = insert(:subscribed_viewer, organization: org)

    %{org: org, viewer: viewer}
  end

  describe "unauthenticated access" do
    test "redirects to /login", %{org: org} do
      conn =
        build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")
        |> init_test_session(%{})

      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/history")
      assert path == ~p"/login"
    end
  end

  describe "subscription gating" do
    test "unsubscribed viewer is redirected to /subscribe", %{org: org} do
      viewer = insert(:viewer, organization: org, subscription_status: "none")
      {:error, {:redirect, %{to: path}}} = live(conn_for_viewer(viewer), ~p"/history")
      assert path == "/subscribe"
    end
  end

  describe "load_more pagination" do
    test "load more button appears when there are multiple pages", %{org: org, viewer: viewer} do
      # Create 25 history entries (more than per_page: 24)
      for i <- 1..25 do
        video = insert(:video, organization: org, title: "Video #{i}", mux_status: "ready")

        insert(:watch_history,
          organization: org,
          viewer: viewer,
          video: video,
          watched_at:
            DateTime.utc_now()
            |> DateTime.add(-i * 60, :second)
            |> DateTime.truncate(:second)
        )
      end

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/history")
      assert html =~ ~s(data-test="load-more-btn")
    end

    test "load more button hidden when all entries fit on one page", %{org: org, viewer: viewer} do
      video = insert(:video, organization: org, title: "Solo Video", mux_status: "ready")

      insert(:watch_history,
        organization: org,
        viewer: viewer,
        video: video,
        watched_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/history")
      refute html =~ ~s(data-test="load-more-btn")
    end

    test "clicking load more appends more entries", %{org: org, viewer: viewer} do
      for i <- 1..25 do
        video = insert(:video, organization: org, title: "Hist #{i}", mux_status: "ready")

        insert(:watch_history,
          organization: org,
          viewer: viewer,
          video: video,
          watched_at:
            DateTime.utc_now()
            |> DateTime.add(-i * 60, :second)
            |> DateTime.truncate(:second)
        )
      end

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/history")
      view |> element(~s([data-test="load-more-btn"])) |> render_click()

      html = render(view)
      # After loading more, all 25 should be visible
      assert html =~ "Hist 25"
    end
  end

  describe "multi-tenant isolation" do
    test "history only shows entries from the viewer's org", %{org: org, viewer: viewer} do
      video = insert(:video, organization: org, title: "Org A History", mux_status: "ready")

      insert(:watch_history,
        organization: org,
        viewer: viewer,
        video: video,
        watched_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      other_org = insert(:organization)
      other_viewer = insert(:subscribed_viewer, organization: other_org)

      {:ok, _view, html} = live(conn_for_viewer(other_viewer), ~p"/history")
      refute html =~ "Org A History"
      assert html =~ "No watch history yet"
    end
  end

  describe "relative time formatting" do
    test "shows 'Just now' for recent entries", %{org: org, viewer: viewer} do
      video = insert(:video, organization: org, title: "Recent", mux_status: "ready")

      insert(:watch_history,
        organization: org,
        viewer: viewer,
        video: video,
        watched_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/history")
      assert html =~ "Just now"
    end
  end
end
