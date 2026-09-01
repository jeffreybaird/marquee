defmodule MarqueeWeb.Hooks.AssignViewerScopeTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "require_authenticated via /account" do
    test "valid viewer session assigns viewer and renders account page", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/account")
      assert html =~ "Account"
      assert html =~ viewer.email
    end

    test "no viewer session redirects to /login", %{conn: _conn} do
      org = insert(:organization)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/account")
    end

    test "suspended viewer redirected with error", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, status: :suspended)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn_for_viewer(viewer), ~p"/account")
    end

    test "banned viewer redirected with error", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, status: :banned)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn_for_viewer(viewer), ~p"/account")
    end
  end
end
