defmodule MarqueeWeb.Admin.VideoAnalyticsLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "access control" do
    test "admin can access a video analytics page" do
      membership = insert(:membership, role: :admin)
      video = insert(:video, organization: membership.organization, title: "Case Study")

      {:ok, _view, html} =
        live(conn_for(membership), ~p"/admin/analytics/videos/#{video.id}")

      assert html =~ "Case Study"
    end

    test "viewer_support can access a video analytics page" do
      membership = insert(:membership, role: :viewer_support)
      video = insert(:video, organization: membership.organization)

      {:ok, _view, _html} =
        live(conn_for(membership), ~p"/admin/analytics/videos/#{video.id}")
    end

    test "unauthenticated user is redirected to login" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      conn = Phoenix.ConnTest.build_conn() |> Map.put(:host, "#{org.slug}.localhost")

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/admin/analytics/videos/#{video.id}")

      assert path == ~p"/users/log-in"
    end
  end

  describe "mount and render" do
    test "redirects with flash when video does not exist" do
      membership = insert(:membership, role: :admin)
      missing_id = Ecto.UUID.generate()

      assert {:error, {:live_redirect, %{to: "/admin/analytics"}}} =
               live(conn_for(membership), ~p"/admin/analytics/videos/#{missing_id}")
    end

    test "org A cannot view org B video analytics" do
      membership_a = insert(:membership, role: :admin)
      org_b = insert(:organization)
      video_b = insert(:video, organization: org_b, title: "Secret")

      assert {:error, {:live_redirect, %{to: "/admin/analytics"}}} =
               live(conn_for(membership_a), ~p"/admin/analytics/videos/#{video_b.id}")
    end

    test "shows empty state when video has no drop-off data" do
      membership = insert(:membership, role: :admin)
      video = insert(:video, organization: membership.organization)

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/analytics/videos/#{video.id}")

      assert has_element?(view, "[data-test='drop-off-empty-state']")
      refute has_element?(view, "[data-test='drop-off-chart']")
    end

    test "renders watch stats KPI cards" do
      membership = insert(:membership, role: :admin)
      video = insert(:video, organization: membership.organization, duration: 120.0)
      viewer = insert(:subscribed_viewer, organization: membership.organization)

      insert(:progress,
        organization: membership.organization,
        video: video,
        viewer: viewer,
        position: 60.0,
        duration: 120.0
      )

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/analytics/videos/#{video.id}")

      assert has_element?(view, "[data-test='kpi-unique-viewers']", "1")
      assert has_element?(view, "[data-test='kpi-avg-watch-pct']", "50.0%")
    end

    test "renders drop-off KPI cards and chart when data exists" do
      membership = insert(:membership, role: :admin)
      video = insert(:video, organization: membership.organization)

      insert(:video_drop_off_bucket,
        organization: membership.organization,
        video: video,
        bucket: 4,
        count: 3
      )

      insert(:video_drop_off_bucket,
        organization: membership.organization,
        video: video,
        bucket: 9,
        count: 7
      )

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/analytics/videos/#{video.id}")

      assert has_element?(view, "[data-test='kpi-total-drop-offs']", "10")
      assert has_element?(view, "[data-test='kpi-drop-off-time']", "1:30–1:40")
      assert has_element?(view, "[data-test='drop-off-chart']")
      refute has_element?(view, "[data-test='drop-off-empty-state']")
    end
  end
end
