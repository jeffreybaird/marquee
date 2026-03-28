defmodule BobineWeb.Admin.SettingsLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "access control" do
    test "admin can access settings page", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/settings")
      assert html =~ "Settings"
    end

    test "viewer_support can access settings page", %{conn: _conn} do
      membership = insert(:membership, role: :viewer_support)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/settings")
      assert html =~ "Settings"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/settings")
      assert path == ~p"/users/log-in"
    end

    test "displays organization name", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/settings")
      assert has_element?(view, "[data-test='org-name']", membership.organization.name)
    end
  end
end
