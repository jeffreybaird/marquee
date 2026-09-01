defmodule MarqueeWeb.Viewer.ViewAllLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /browse/popular" do
    test "renders popular title and videos", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, title: "Hot Video", mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse/popular")
      assert html =~ "Popular"
      assert html =~ "Hot Video"
      assert html =~ ~s(data-test="sv-view-all-header")
      assert html =~ ~s(data-test="sv-view-all-title")
    end

    test "does not show videos from other orgs", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      insert(:video, organization: org, title: "Our Video", mux_status: "ready")
      insert(:video, organization: other_org, title: "Their Video", mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse/popular")
      assert html =~ "Our Video"
      refute html =~ "Their Video"
    end

    test "shows empty state when no videos exist", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse/popular")
      assert html =~ "No videos available"
    end
  end

  describe "GET /browse/recent" do
    test "renders recently added title and videos", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, title: "New Release", mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse/recent")
      assert html =~ "Recently Added"
      assert html =~ "New Release"
      assert html =~ ~s(data-test="sv-view-all-grid")
    end
  end

  describe "GET /browse/:source with invalid source" do
    test "redirects to home for unknown source", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), "/browse/invalid")
    end
  end
end
