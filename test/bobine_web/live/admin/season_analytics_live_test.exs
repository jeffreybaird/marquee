defmodule BobineWeb.Admin.SeasonAnalyticsLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp build_season(membership) do
    org = membership.organization
    series = insert(:series, organization: org, title: "Demo Series")
    season = insert(:season, organization: org, series: series, season_number: 1, title: "Pilot")
    %{org: org, series: series, season: season}
  end

  describe "access control" do
    test "admin can access season analytics page" do
      membership = insert(:membership, role: :admin)
      %{series: series, season: season} = build_season(membership)

      {:ok, _view, html} =
        live(conn_for(membership), ~p"/admin/analytics/series/#{series.id}/seasons/#{season.id}")

      assert html =~ "Pilot"
      assert html =~ "Demo Series"
    end
  end

  describe "mount and render" do
    test "redirects when season doesn't belong to series" do
      membership = insert(:membership, role: :admin)
      series = insert(:series, organization: membership.organization)
      other_series = insert(:series, organization: membership.organization)
      season = insert(:season, organization: membership.organization, series: other_series)

      assert {:error, {:live_redirect, %{to: "/admin/analytics"}}} =
               live(
                 conn_for(membership),
                 ~p"/admin/analytics/series/#{series.id}/seasons/#{season.id}"
               )
    end

    test "org A cannot view org B season analytics" do
      membership_a = insert(:membership, role: :admin)
      org_b = insert(:organization)
      series_b = insert(:series, organization: org_b)
      season_b = insert(:season, organization: org_b, series: series_b)

      assert {:error, {:live_redirect, %{to: "/admin/analytics"}}} =
               live(
                 conn_for(membership_a),
                 ~p"/admin/analytics/series/#{series_b.id}/seasons/#{season_b.id}"
               )
    end

    test "shows funnel empty state when season has no episodes" do
      membership = insert(:membership, role: :admin)
      %{series: series, season: season} = build_season(membership)

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/analytics/series/#{series.id}/seasons/#{season.id}")

      assert has_element?(view, "[data-test='funnel-empty-state']")
    end

    test "renders KPIs, drill elements, and no-next-season message" do
      membership = insert(:membership, role: :admin)
      %{org: org, series: series, season: season} = build_season(membership)

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
        live(conn_for(membership), ~p"/admin/analytics/series/#{series.id}/seasons/#{season.id}")

      assert has_element?(view, "[data-test='kpi-starters']", "1")
      assert has_element?(view, "[data-test='kpi-finishers']", "1")
      assert has_element?(view, "[data-test='kpi-completion-rate']", "100.0%")
      assert has_element?(view, "[data-test='episode-funnel-chart']")
      assert has_element?(view, "[data-test='next-season-none']")
    end

    test "shows next-season rate when a next season exists" do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      series = insert(:series, organization: org)
      season1 = insert(:season, organization: org, series: series, season_number: 1)
      season2 = insert(:season, organization: org, series: series, season_number: 2)

      s1_video = insert(:video, organization: org)
      s2_video = insert(:video, organization: org, duration: 1000.0)

      insert(:episode, organization: org, season: season1, video: s1_video, episode_number: 1)
      insert(:episode, organization: org, season: season2, video: s2_video, episode_number: 1)

      viewer = insert(:viewer, organization: org)

      insert(:progress,
        organization: org,
        video: s1_video,
        viewer: viewer,
        user: nil,
        completed: true,
        position: 0.0
      )

      insert(:progress,
        organization: org,
        video: s2_video,
        viewer: viewer,
        user: nil,
        position: 300.0,
        duration: 1000.0
      )

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/analytics/series/#{series.id}/seasons/#{season1.id}")

      assert has_element?(view, "[data-test='next-season-rate']", "100.0%")
      refute has_element?(view, "[data-test='next-season-none']")
    end
  end

  describe "set_period event" do
    test "period selector reloads data" do
      membership = insert(:membership, role: :admin)
      %{series: series, season: season} = build_season(membership)

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/analytics/series/#{series.id}/seasons/#{season.id}")

      render_click(view, "set_period", %{"period" => "7"})
      seven_btn = element(view, "[data-test='period-selector-7']")
      assert render(seven_btn) =~ "bg-admin-accent"
    end
  end
end
