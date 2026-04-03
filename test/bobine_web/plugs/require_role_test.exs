defmodule BobineWeb.Plugs.RequireRoleTest do
  use BobineWeb.ConnCase, async: true

  alias Bobine.Accounts.Scope
  alias BobineWeb.Plugs.RequireRole

  # The RequireRole plug calls put_flash, which requires flash to be fetched.
  # Simulate the browser pipeline setup for plug unit tests.
  setup %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Phoenix.LiveView.Router.fetch_live_flash([])

    {:ok, conn: conn}
  end

  defp conn_with_membership(conn, role) do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, user: user, organization: org, role: role)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    assign(conn, :current_scope, scope)
  end

  describe "allow access" do
    test "allows owner when minimum is viewer_support", %{conn: conn} do
      conn =
        conn |> conn_with_membership(:owner) |> RequireRole.call(minimum_role: :viewer_support)

      refute conn.halted
    end

    test "allows admin when minimum is admin", %{conn: conn} do
      conn = conn |> conn_with_membership(:admin) |> RequireRole.call(minimum_role: :admin)
      refute conn.halted
    end

    test "allows editor when minimum is editor", %{conn: conn} do
      conn = conn |> conn_with_membership(:editor) |> RequireRole.call(minimum_role: :editor)
      refute conn.halted
    end

    test "allows viewer_support when minimum is viewer_support", %{conn: conn} do
      conn =
        conn
        |> conn_with_membership(:viewer_support)
        |> RequireRole.call(minimum_role: :viewer_support)

      refute conn.halted
    end

    test "owner can access editor-minimum routes", %{conn: conn} do
      conn = conn |> conn_with_membership(:owner) |> RequireRole.call(minimum_role: :editor)
      refute conn.halted
    end
  end

  describe "deny access" do
    test "denies editor when minimum is admin", %{conn: conn} do
      conn = conn |> conn_with_membership(:editor) |> RequireRole.call(minimum_role: :admin)
      assert conn.halted
    end

    test "denies viewer_support when minimum is editor", %{conn: conn} do
      conn =
        conn
        |> conn_with_membership(:viewer_support)
        |> RequireRole.call(minimum_role: :editor)

      assert conn.halted
    end

    test "viewer_support cannot access admin-minimum routes", %{conn: conn} do
      conn =
        conn |> conn_with_membership(:viewer_support) |> RequireRole.call(minimum_role: :admin)

      assert conn.halted
    end
  end

  describe "unauthenticated" do
    test "halts unauthenticated user with no scope", %{conn: conn} do
      conn = conn |> RequireRole.call(minimum_role: :viewer_support)
      assert conn.halted
    end

    test "halts when scope has no membership", %{conn: conn} do
      user = insert(:user)
      scope = Scope.for_user(user)

      conn =
        conn
        |> assign(:current_scope, scope)
        |> RequireRole.call(minimum_role: :viewer_support)

      assert conn.halted
    end
  end
end
