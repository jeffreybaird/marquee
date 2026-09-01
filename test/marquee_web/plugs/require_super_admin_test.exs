defmodule MarqueeWeb.Plugs.RequireSuperAdminTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveView.Router, only: [fetch_live_flash: 2]

  alias Marquee.Accounts.Scope
  alias MarqueeWeb.Plugs.RequireSuperAdmin

  setup do
    conn =
      build_conn()
      |> init_test_session(%{})
      |> fetch_live_flash([])

    {:ok, conn: conn}
  end

  test "allows super admin user through", %{conn: conn} do
    super_admin = insert(:super_admin)
    scope = Scope.for_user(super_admin)

    conn =
      conn
      |> Plug.Conn.assign(:current_scope, scope)
      |> RequireSuperAdmin.call([])

    refute conn.halted
  end

  test "redirects regular user to /", %{conn: conn} do
    user = insert(:user, is_super_admin: false)
    scope = Scope.for_user(user)

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
