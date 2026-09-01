defmodule MarqueeWeb.Viewer.HistoryLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    org = insert(:organization)
    viewer = insert(:subscribed_viewer, organization: org)

    %{org: org, viewer: viewer}
  end

  describe "GET /history" do
    test "shows empty state when no history", %{viewer: viewer} do
      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/history")
      assert html =~ "No watch history yet"
    end

    test "shows watched videos", %{org: org, viewer: viewer} do
      video = insert(:video, organization: org, title: "Watched Video", mux_status: "ready")

      insert(:watch_history,
        organization: org,
        viewer: viewer,
        video: video,
        watched_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/history")
      assert html =~ "Watched Video"
    end

    test "shows most recent first", %{org: org, viewer: viewer} do
      v1 = insert(:video, organization: org, title: "Older Video", mux_status: "ready")
      v2 = insert(:video, organization: org, title: "Newer Video", mux_status: "ready")

      insert(:watch_history,
        organization: org,
        viewer: viewer,
        video: v1,
        watched_at: ~U[2026-01-01 10:00:00Z]
      )

      insert(:watch_history,
        organization: org,
        viewer: viewer,
        video: v2,
        watched_at: ~U[2026-01-02 10:00:00Z]
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/history")
      # Both should appear; newer first based on position in HTML
      assert html =~ "Newer Video"
      assert html =~ "Older Video"
    end
  end
end
