defmodule BobineWeb.Plugs.RequireSuperAdminTest do
  use BobineWeb.ConnCase, async: true

  alias BobineWeb.Plugs.RequireSuperAdmin

  setup do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Phoenix.LiveView.Router.fetch_live_flash([])

    {:ok, conn: conn}
  end

  test "allows super admin user through", %{conn: conn} do
    super_admin = insert(:super_admin)
    scope = Bobine.Accounts.Scope.for_user(super_admin)

    conn =
      conn
      |> Plug.Conn.assign(:current_scope, scope)
      |> RequireSuperAdmin.call([])

    refute conn.halted
  end

  test "redirects regular user to /", %{conn: conn} do
    user = insert(:user, is_super_admin: false)
    scope = Bobine.Accounts.Scope.for_user(user)

    conn =
      conn
      |> Plug.Conn.assign(:current_scope, scope)
      |> RequireSuperAdmin.call([])

    assert conn.halted
    assert redirected_to(conn) == "/"
  end

  test "redirects unauthenticated request to /", %{conn: conn} do
    conn =
      conn
      |> Plug.Conn.assign(:current_scope, nil)
      |> RequireSuperAdmin.call([])

    assert conn.halted
    assert redirected_to(conn) == "/"
  end
end
