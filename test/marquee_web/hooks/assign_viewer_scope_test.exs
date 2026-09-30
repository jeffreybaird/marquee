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

  describe "viewer session is only honored for the viewer's own organization" do
    test "viewer session on a page resolved to a different org is treated as logged out (require_authenticated)",
         %{conn: _conn} do
      org_a = insert(:organization)
      org_b = insert(:organization)
      viewer = insert(:viewer, organization: org_a)

      conn = viewer |> conn_for_viewer() |> Map.put(:host, "#{org_b.slug}.localhost")

      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/account")
    end

    test "viewer session on a public page resolved to a different org shows the signed-out UI",
         %{conn: _conn} do
      org_a = insert(:organization)
      org_b = insert(:organization)
      viewer = insert(:viewer, organization: org_a)

      conn = viewer |> conn_for_viewer() |> Map.put(:host, "#{org_b.slug}.localhost")

      {:ok, view, _html} = live(conn, ~p"/browse")
      assert has_element?(view, "[data-test=sign-in-link]")
    end

    test "viewer session on a page where no organization resolves is treated as logged out",
         %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      token = Marquee.Viewers.generate_viewer_session_token(viewer)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session(:viewer_token, token)

      # An explicit ?org= that does not resolve leaves the home page with a nil
      # organization. A resolved viewer would be redirected to their org home;
      # a logged-out visitor sees the platform marketing page instead.
      {:ok, view, _html} = live(conn, ~p"/?org=no-such-org")
      assert has_element?(view, "[data-test=platform-marketing]")
    end
  end
end
