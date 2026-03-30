defmodule BobineWeb.Super.DashboardLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "responsive layout" do
    test "mobile sidebar toggle uses JS commands, not checkbox", %{conn: _conn} do
      # Regression: CSS-only peer-checked drawer broke under LiveView DOM patching.
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, _view, html} = live(conn, ~p"/super")

      assert html =~ ~s(id="super-sidebar")
      assert html =~ ~s(id="super-overlay")
      assert html =~ "hero-bars-3"
      assert html =~ "phx-click"
      refute html =~ ~s(id="super-drawer")
    end
  end

  describe "GET /super" do
    test "super admin can access dashboard", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, _view, html} = live(conn, ~p"/super")
      assert html =~ "Platform Dashboard"
    end

    test "dashboard displays platform stats", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)
      insert(:video, organization: org)
      insert(:subscription, organization: org, status: :active)

      {:ok, _view, html} = live(conn, ~p"/super")
      assert html =~ ~s(data-test="stat-total-orgs")
      assert html =~ ~s(data-test="stat-total-users")
      assert html =~ ~s(data-test="stat-total-videos")
      assert html =~ ~s(data-test="stat-total-subscribers")
    end

    test "non-super-admin user is redirected", %{conn: _conn} do
      user = insert(:user, is_super_admin: false)
      membership = insert(:membership, user: user)
      conn = conn_for(membership)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/super")
    end

    test "unauthenticated user is redirected to log in" do
      conn = build_conn()
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/super")
    end
  end
end
