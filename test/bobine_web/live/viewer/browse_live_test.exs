defmodule BobineWeb.Viewer.BrowseLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /browse" do
    test "renders browse page with grid", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, title: "Browse Video", mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse")
      assert html =~ "Browse"
      assert html =~ ~s(data-test="sv-browse-grid")
      assert html =~ "Browse Video"
    end

    test "renders search input", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse")
      assert html =~ ~s(data-test="sv-search-input")
    end

    test "renders sort selector", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse")
      assert html =~ ~s(data-test="sv-filter-sort")
    end

    test "shows empty state when no videos", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse")
      assert html =~ ~s(data-test="sv-empty-state")
      assert html =~ "No videos found"
    end

    test "search filters videos by title", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, title: "Alpha Video", mux_status: "ready")
      insert(:video, organization: org, title: "Beta Movie", mux_status: "ready")

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/browse")

      html = render_change(view, "filter", %{"search" => "Alpha", "sort" => "newest"})
      assert html =~ "Alpha Video"
      refute html =~ "Beta Movie"
    end

    test "sort changes order", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, title: "Zebra", mux_status: "ready")
      insert(:video, organization: org, title: "Aardvark", mux_status: "ready")

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/browse")

      html = render_change(view, "filter", %{"search" => "", "sort" => "alphabetical"})
      aardvark_pos = :binary.match(html, "Aardvark") |> elem(0)
      zebra_pos = :binary.match(html, "Zebra") |> elem(0)
      assert aardvark_pos < zebra_pos
    end

    test "does not show videos from other org", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      insert(:video, organization: org, title: "Our Video", mux_status: "ready")
      insert(:video, organization: other_org, title: "Other Video", mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse")
      assert html =~ "Our Video"
      refute html =~ "Other Video"
    end
  end
end
