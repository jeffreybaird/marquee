defmodule BobineWeb.Admin.ContentLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "access control" do
    test "admin can access content page", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ "Content"
    end

    test "editor can access content page", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ "Content"
    end

    test "viewer_support can access content page", %{conn: _conn} do
      membership = insert(:membership, role: :viewer_support)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ "Content"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/content")
      assert path == ~p"/users/log-in"
    end

    test "displays organization name", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")
      assert has_element?(view, "[data-test='org-name']", membership.organization.name)
    end
  end
end
