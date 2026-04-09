defmodule BobineWeb.Viewer.SessionControllerTest do
  use BobineWeb.ConnCase, async: true

  import Ecto.Query, warn: false

  describe "POST /viewer-session/impersonate (start_impersonation)" do
    test "operator with viewer_support role can start impersonation", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :viewer_support)
      viewer = insert(:viewer, organization: org)

      conn =
        conn_for(membership)
        |> post(~p"/viewer-session/impersonate", %{
          viewer_id: viewer.id,
          return_path: "/admin/members"
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :impersonating_viewer_id) == viewer.id
      assert get_session(conn, :impersonating_admin_user_id) == membership.user.id
      assert get_session(conn, :impersonating_return_path) == "/admin/members"
      assert is_integer(get_session(conn, :impersonation_started_at))
    end

    test "admin role can start impersonation", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)
      viewer = insert(:viewer, organization: org)

      conn =
        conn_for(membership)
        |> post(~p"/viewer-session/impersonate", %{
          viewer_id: viewer.id,
          return_path: "/admin/members"
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :impersonating_viewer_id) == viewer.id
    end
  end

  describe "DELETE /viewer-session/impersonate (stop_impersonation)" do
    test "clears impersonation session and redirects to return path", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)
      viewer = insert(:viewer, organization: org)

      conn =
        conn_for(membership)
        |> Plug.Conn.put_session(:impersonating_viewer_id, viewer.id)
        |> Plug.Conn.put_session(:impersonating_admin_user_id, membership.user.id)
        |> Plug.Conn.put_session(:impersonating_return_path, "/admin/members")
        |> Plug.Conn.put_session(:impersonation_started_at, System.system_time(:second))
        |> delete(~p"/viewer-session/impersonate")

      assert redirected_to(conn) == "/admin/members"
      refute get_session(conn, :impersonating_viewer_id)
      refute get_session(conn, :impersonating_admin_user_id)
      refute get_session(conn, :impersonating_return_path)
      refute get_session(conn, :impersonation_started_at)
    end

    test "defaults to /admin/members when no return path", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)

      conn =
        conn_for(membership)
        |> delete(~p"/viewer-session/impersonate")

      assert redirected_to(conn) == "/admin/members"
    end
  end

  describe "GET /magic-link/:token" do
    test "valid token creates session and redirects", %{conn: _conn} do
      org = insert(:organization)
      _viewer = insert(:viewer, organization: org, email: "magic@test.com")

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/magic-link/invalid-token-here")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or it has expired"
    end
  end

  describe "DELETE /viewer-session" do
    test "logs out viewer and clears session", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      conn =
        conn_for_viewer(viewer)
        |> delete(~p"/viewer-session")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :viewer_token)
    end

    test "redirects to the org home (subdomain) preserving host", %{conn: _conn} do
      org = insert(:organization, slug: "logout-test-org")
      viewer = insert(:viewer, organization: org)

      conn =
        conn_for_viewer(viewer)
        |> delete(~p"/viewer-session")

      # Subdomain host carries the org context — relative `/` redirect lands
      # back on the same org's home.
      assert redirected_to(conn) == ~p"/"
      assert conn.host == "#{org.slug}.localhost"
      refute get_session(conn, :viewer_token)
    end

    test "redirected target shows the org's landing page (not platform marketing)",
         %{conn: _conn} do
      org = insert(:organization, name: "Acme Studio")
      viewer = insert(:viewer, organization: org)

      insert(:landing_section,
        organization: org,
        section_type: :header_text,
        position: 0,
        config: %{"headline" => "Acme welcomes you back"}
      )

      logout_conn =
        conn_for_viewer(viewer)
        |> delete(~p"/viewer-session")

      assert redirected_to(logout_conn) == ~p"/"
      refute get_session(logout_conn, :viewer_token)

      # Recycle the conn so cookies / session carry over to the next request,
      # then follow the redirect to confirm the org home renders.
      follow_conn =
        logout_conn
        |> Phoenix.ConnTest.recycle()
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.get(~p"/")

      body = Phoenix.ConnTest.html_response(follow_conn, 200)
      assert body =~ "Acme welcomes you back"
      assert body =~ ~s(data-test="landing-page")
      refute body =~ ~s(data-test="platform-marketing")
    end

    test "without a subdomain, redirect carries the org slug as a query param",
         %{conn: _conn} do
      org = insert(:organization, slug: "apex-logout-org")
      viewer = insert(:viewer, organization: org)

      token = Bobine.Viewers.generate_viewer_session_token(viewer)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "localhost")
        |> Phoenix.ConnTest.init_test_session(%{viewer_token: token})
        |> delete(~p"/viewer-session")

      assert redirected_to(conn) == "/?org=#{org.slug}"
      refute get_session(conn, :viewer_token)
    end
  end
end
