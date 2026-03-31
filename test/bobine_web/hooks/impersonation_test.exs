defmodule BobineWeb.Hooks.ImpersonationTest do
  @moduledoc """
  Tests for viewer impersonation via AssignViewerScope hook.
  Covers RBAC, expiry, and impersonation state in LiveView.
  """
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "impersonation RBAC" do
    test "admin can impersonate viewers on their org", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      membership = insert(:membership, organization: org, role: :admin)

      conn = conn_for_impersonating_viewer(membership, viewer)
      {:ok, view, html} = live(conn, ~p"/account")

      assert html =~ viewer.email
      assert has_element?(view, "[data-test='impersonation-banner']")
    end

    test "viewer_support can impersonate viewers on their org", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      membership = insert(:membership, organization: org, role: :viewer_support)

      conn = conn_for_impersonating_viewer(membership, viewer)
      {:ok, view, html} = live(conn, ~p"/account")

      assert html =~ viewer.email
      assert has_element?(view, "[data-test='impersonation-banner']")
    end

    test "editor cannot impersonate — impersonation is ignored", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      membership = insert(:membership, organization: org, role: :editor)

      # Build conn with impersonation session keys but editor role
      conn =
        conn_for(membership)
        |> Plug.Conn.put_session(:impersonating_viewer_id, viewer.id)
        |> Plug.Conn.put_session(:impersonating_admin_user_id, membership.user.id)
        |> Plug.Conn.put_session(:impersonating_return_path, "/admin/members")
        |> Plug.Conn.put_session(:impersonation_started_at, System.system_time(:second))

      # The /account page requires viewer auth, so without a valid viewer session
      # this should redirect to /login (editor is not a viewer, and impersonation
      # is not authorized for editor role)
      result = live(conn, ~p"/account")

      case result do
        {:error, {:redirect, %{to: "/login"}}} ->
          assert true

        {:ok, view, _html} ->
          # If we get here, impersonation was ignored and the page loaded
          # without viewer context — banner should not be present
          refute has_element?(view, "[data-test='impersonation-banner']")
      end
    end

    test "operator from different org cannot impersonate viewer", %{conn: _conn} do
      org_a = insert(:organization)
      org_b = insert(:organization)
      viewer = insert(:viewer, organization: org_a)
      membership = insert(:membership, organization: org_b, role: :admin)

      conn =
        conn_for(membership)
        |> Plug.Conn.put_session(:impersonating_viewer_id, viewer.id)
        |> Plug.Conn.put_session(:impersonating_admin_user_id, membership.user.id)
        |> Plug.Conn.put_session(:impersonating_return_path, "/admin/members")
        |> Plug.Conn.put_session(:impersonation_started_at, System.system_time(:second))

      # Should redirect to /login because impersonation is not authorized
      result = live(conn, ~p"/account")

      case result do
        {:error, {:redirect, %{to: "/login"}}} ->
          assert true

        {:ok, view, _html} ->
          refute has_element?(view, "[data-test='impersonation-banner']")
      end
    end

    test "super admin can impersonate viewers on any org", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      super_admin = insert(:super_admin)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session(:impersonating_viewer_id, viewer.id)
        |> Plug.Conn.put_session(:impersonating_admin_user_id, super_admin.id)
        |> Plug.Conn.put_session(:impersonating_return_path, "/super")
        |> Plug.Conn.put_session(:impersonation_started_at, System.system_time(:second))

      {:ok, view, html} = live(conn, ~p"/account")
      assert html =~ viewer.email
      assert has_element?(view, "[data-test='impersonation-banner']")
    end
  end

  describe "impersonation expiry" do
    test "expired impersonation is ignored", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      membership = insert(:membership, organization: org, role: :admin)

      # Set started_at to 2 hours ago (exceeds 3600s max age)
      expired_at = System.system_time(:second) - 7200

      conn =
        conn_for(membership)
        |> Plug.Conn.put_session(:impersonating_viewer_id, viewer.id)
        |> Plug.Conn.put_session(:impersonating_admin_user_id, membership.user.id)
        |> Plug.Conn.put_session(:impersonating_return_path, "/admin/members")
        |> Plug.Conn.put_session(:impersonation_started_at, expired_at)

      # With expired impersonation, viewer session is nil, so should redirect to /login
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/account")
    end
  end

  describe "session isolation" do
    test "operator session and viewer session do not interfere", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      membership = insert(:membership, organization: org, role: :admin)

      # Operator can access admin
      {:ok, _view, admin_html} = live(conn_for(membership), ~p"/admin/members")
      assert admin_html =~ "Members"

      # Viewer can access account
      {:ok, _view, viewer_html} = live(conn_for_viewer(viewer), ~p"/account")
      assert viewer_html =~ "Account"
    end
  end
end
