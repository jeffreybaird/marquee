defmodule BobineWeb.Super.ImpersonationTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "impersonation flow" do
    test "super admin can start impersonation and session is updated", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)

      conn = post(conn, ~p"/super/organizations/#{org.id}/impersonate")

      assert redirected_to(conn) == "/admin"
      assert get_session(conn, :impersonated_org_id) == org.id
    end

    test "impersonation banner visible when impersonating", %{conn: conn} do
      super_admin = insert(:super_admin)
      org = insert(:organization, name: "Target Org", slug: "target-org")

      # Build a conn with impersonated_org_id already in session (simulating post-start state)
      conn =
        conn_for_super_admin(super_admin)
        |> Plug.Conn.put_session(:impersonated_org_id, org.id)

      {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ ~s(data-test="impersonation-banner")
      assert html =~ "Target Org"
    end

    test "stop impersonation clears session and redirects to super admin panel", %{conn: conn} do
      super_admin = insert(:super_admin)
      org = insert(:organization)

      conn =
        conn_for_super_admin(super_admin)
        |> Plug.Conn.put_session(:impersonated_org_id, org.id)
        |> delete(~p"/super/impersonate")

      assert redirected_to(conn) == "/super/organizations"
      refute get_session(conn, :impersonated_org_id)
    end

    test "non-super-admin cannot trigger impersonation", %{conn: conn} do
      org = insert(:organization)
      user = insert(:user, is_super_admin: false)
      membership = insert(:membership, organization: org, user: user, role: :owner)
      conn = conn_for(membership)

      conn = post(conn, ~p"/super/organizations/#{org.id}/impersonate")
      assert redirected_to(conn) == "/"
    end

    test "stop impersonating link visible during impersonation", %{conn: conn} do
      super_admin = insert(:super_admin)
      org = insert(:organization, name: "Org To View", slug: "org-to-view")

      conn =
        conn_for_super_admin(super_admin)
        |> Plug.Conn.put_session(:impersonated_org_id, org.id)

      {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ ~s(data-test="stop-impersonating-btn")
    end
  end
end
