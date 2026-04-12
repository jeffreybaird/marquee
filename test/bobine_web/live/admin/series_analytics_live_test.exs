defmodule BobineWeb.Admin.SeriesAnalyticsLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "access control" do
    test "admin can access series analytics page" do
      membership = insert(:membership, role: :admin)
      series = insert(:series, organization: membership.organization, title: "Demo Series")

      {:ok, _view, html} =
        live(conn_for(membership), ~p"/admin/analytics/series/#{series.id}")

      assert html =~ "Demo Series"
    end

    test "viewer_support can access series analytics page" do
      membership = insert(:membership, role: :viewer_support)
      series = insert(:series, organization: membership.organization)

      {:ok, _view, _html} =
        live(conn_for(membership), ~p"/admin/analytics/series/#{series.id}")
    end
  end

  describe "mount and render" do
    test "redirects with flash when series is missing" do
      membership = insert(:membership, role: :admin)
      missing_id = Ecto.UUID.generate()

      assert {:error, {:live_redirect, %{to: "/admin/analytics"}}} =
               live(conn_for(membership), ~p"/admin/analytics/series/#{missing_id}")
    end

    test "org A cannot view org B series analytics" do
      membership_a = insert(:membership, role: :admin)
      org_b = insert(:organization)
      series_b = insert(:series, organization: org_b)

      assert {:error, {:live_redirect, %{to: "/admin/analytics"}}} =
               live(conn_for(membership_a), ~p"/admin/analytics/series/#{series_b.id}")
    end

    test "shows empty state when series has no seasons" do
      membership = insert(:membership, role: :admin)
      series = insert(:series, organization: membership.organization)

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/analytics/series/#{series.id}")

      assert has_element?(view, "[data-test='season-empty-state']")
      assert has_element?(view, "[data-test='kpi-total-seasons']", "0")
    end

    test "renders per-season rows with drill-in link" do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      series = insert(:series, organization: org)
      season = insert(:season, organization: org, series: series, season_number: 1, title: "S1")

      video = insert(:video, organization: org)
      insert(:episode, organization: org, season: season, video: video, episode_number: 1)

      viewer = insert(:viewer, organization: org)

      insert(:progress,
        organization: org,
        video: video,
        viewer: viewer,
        user: nil,
        completed: true,
        position: 0.0
      )

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/analytics/series/#{series.id}")

      assert has_element?(view, "[data-test='season-row-#{season.id}']")
      assert has_element?(view, "[data-test='kpi-total-seasons']", "1")
      assert has_element?(view, "[data-test='kpi-total-starters']", "1")
      assert has_element?(view, "[data-test='kpi-total-finishers']", "1")
      assert has_element?(view, "[data-test='kpi-overall-completion']", "100.0%")
      assert has_element?(view, "[data-test='season-drill-#{season.id}']")
    end
  end

  describe "set_period event" do
    test "period selector reloads season stats" do
      membership = insert(:membership, role: :admin)
      series = insert(:series, organization: membership.organization)

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/analytics/series/#{series.id}")

      html = render_click(view, "set_period", %{"period" => "7"})
      assert html =~ "Analytics"

      seven_btn = element(view, "[data-test='period-selector-7']")
      assert render(seven_btn) =~ "btn-primary"
    end
  end
end
