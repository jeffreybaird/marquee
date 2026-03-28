defmodule BobineWeb.Admin.AnalyticsLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "access control" do
    test "admin can access analytics page", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/analytics")
      assert html =~ "Analytics"
    end

    test "viewer_support can access analytics page", %{conn: _conn} do
      membership = insert(:membership, role: :viewer_support)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/analytics")
      assert html =~ "Analytics"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/analytics")
      assert path == ~p"/users/log-in"
    end

    test "displays organization name", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")
      assert has_element?(view, "[data-test='org-name']", membership.organization.name)
    end
  end
end
