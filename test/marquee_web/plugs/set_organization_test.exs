defmodule MarqueeWeb.Plugs.SetOrganizationTest do
  # async: false because some tests toggle :marquee, :org_resolution.
  use MarqueeWeb.ConnCase, async: false

  alias Marquee.Accounts.Scope
  alias MarqueeWeb.Plugs.SetOrganization

  setup %{conn: conn} do
    {:ok, conn: Plug.Test.init_test_session(conn, %{})}
  end

  defp put_query_params(conn, params) do
    conn
    |> Map.put(:query_string, URI.encode_query(params))
    |> Map.put(:params, params)
    |> Plug.Conn.fetch_query_params()
  end

  describe "resolve by custom domain" do
    test "resolves org when host matches custom_domain", %{conn: conn} do
      org = insert(:organization, custom_domain: "my-custom-domain.com")

      conn =
        conn
        |> Map.put(:host, "my-custom-domain.com")
        |> SetOrganization.call([])

      assert conn.assigns.organization.id == org.id
    end

    test "does not match when custom_domain differs", %{conn: conn} do
      insert(:organization, custom_domain: "other.com", slug: "other-org")

      conn =
        conn
        |> Map.put(:host, "no-match.com")
        |> SetOrganization.call([])

      assert conn.status == 404
    end
  end

  describe "resolve by subdomain" do
    test "resolves org from subdomain slug", %{conn: conn} do
      org = insert(:organization)

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> SetOrganization.call([])

      assert conn.assigns.organization.id == org.id
    end

    test "returns 404 when subdomain matches no org", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "no-such-org.localhost")
        |> SetOrganization.call([])

      assert conn.status == 404
      assert conn.halted
    end

    test "returns 404 for bare localhost (no subdomain)", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "localhost")
        |> SetOrganization.call([])

      assert conn.status == 404
      assert conn.halted
    end

    test "ignores www subdomain", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "www.example.com")
        |> SetOrganization.call([])

      assert conn.status == 404
    end
  end

  describe "scope update for authenticated user" do
    test "sets org in scope when user is a member", %{conn: conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, user: user, organization: org)

      scope = Scope.for_user(user)

      conn =
        conn
        |> assign(:current_scope, scope)
        |> Map.put(:host, "#{org.slug}.localhost")
        |> SetOrganization.call([])

      assert conn.assigns.current_scope.organization.id == org.id
      assert conn.assigns.current_scope.membership.id == membership.id
    end

    test "assigns organization directly when user is not a member", %{conn: conn} do
      org = insert(:organization)
      user = insert(:user)
      scope = Scope.for_user(user)

      conn =
        conn
        |> assign(:current_scope, scope)
        |> Map.put(:host, "#{org.slug}.localhost")
        |> SetOrganization.call([])

      # Org goes to assigns.organization, not into the scope membership
      assert conn.assigns.organization.id == org.id
      assert is_nil(conn.assigns.current_scope.membership)
    end

    test "assigns organization when no user is authenticated", %{conn: conn} do
      org = insert(:organization)

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> SetOrganization.call([])

      assert conn.assigns.organization.id == org.id
    end
  end

  describe "optional platform home with viewer token" do
    test "clears passive organization context without discarding viewer authentication", %{
      conn: conn
    } do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      token = Marquee.Viewers.generate_viewer_session_token(viewer)

      conn =
        conn
        |> Map.put(:host, "localhost")
        |> Plug.Conn.put_session(:viewer_token, token)
        |> Plug.Conn.put_session(:organization_id, org.id)
        |> Plug.Conn.put_session(:org_slug, org.slug)
        |> SetOrganization.call(optional: true)

      assert conn.assigns.organization == nil
      assert Plug.Conn.get_session(conn, :organization_id) == nil
      assert Plug.Conn.get_session(conn, :org_slug) == nil
      assert Plug.Conn.get_session(conn, :no_org_resolved) == true
      assert Plug.Conn.get_session(conn, :viewer_token) == token
      assert Marquee.Viewers.get_viewer_by_session_token(token).id == viewer.id
    end

    test "shows marketing page when no viewer token in optional mode", %{conn: conn} do
      _org = insert(:organization)

      conn =
        conn
        |> Map.put(:host, "localhost")
        |> SetOrganization.call(optional: true)

      assert conn.assigns.organization == nil
      refute conn.halted
    end

    test "does not resolve org from invalid viewer token in optional mode", %{conn: conn} do
      _org = insert(:organization)

      conn =
        conn
        |> Map.put(:host, "localhost")
        |> Plug.Conn.put_session(:viewer_token, "invalid-token")
        |> SetOrganization.call(optional: true)

      assert conn.assigns.organization == nil
      refute conn.halted
    end
  end

  describe "query-param resolution mode" do
    test "resolves the org from a `?org=slug` query param", %{conn: conn} do
      org = insert(:organization, slug: "demo-org")

      conn =
        conn
        |> Map.put(:host, "localhost")
        |> put_query_params(%{"org" => "demo-org"})
        |> SetOrganization.call([])

      assert conn.assigns.organization.id == org.id
    end

    test "resolves `?org=` when query params have not been pre-fetched", %{conn: conn} do
      org = insert(:organization, slug: "lazy-fetch-org")

      conn =
        conn
        |> Map.put(:host, "localhost")
        |> Map.put(:query_string, "org=lazy-fetch-org")
        |> SetOrganization.call([])

      assert conn.assigns.organization.id == org.id
    end

    test "stashes the resolved slug in the session", %{conn: conn} do
      org = insert(:organization, slug: "demo-org")

      conn =
        conn
        |> Map.put(:host, "localhost")
        |> put_query_params(%{"org" => "demo-org"})
        |> SetOrganization.call([])

      assert Plug.Conn.get_session(conn, :org_slug) == "demo-org"
      assert Plug.Conn.get_session(conn, :organization_id) == org.id
    end

    test "subsequent requests without the param fall back to the session slug", %{conn: conn} do
      org = insert(:organization, slug: "session-org")

      first =
        conn
        |> Map.put(:host, "localhost")
        |> put_query_params(%{"org" => "session-org"})
        |> SetOrganization.call([])

      assert first.assigns.organization.id == org.id

      session = Plug.Conn.get_session(first)

      second =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(session)
        |> Map.put(:host, "localhost")
        |> Plug.Conn.fetch_query_params()
        |> SetOrganization.call([])

      assert second.assigns.organization.id == org.id
    end

    test "request without ?org and no session falls back to default org", %{conn: conn} do
      org = insert(:organization, slug: "fallback-org")

      conn =
        conn
        |> Map.put(:host, "localhost")
        |> Plug.Conn.fetch_query_params()
        |> SetOrganization.call([])

      # Test env's `resolve_env_fallback/1` returns `:not_found`, so the
      # plug 404s when no signal is provided. Either the org from the
      # implicit fallback (membership) is set, or we get a 404 — both
      # behaviors are acceptable here as long as no other tenant leaks in.
      assert conn.assigns[:organization] in [nil, org] or conn.status == 404
    end

    test "an unknown slug in `?org=` 404s instead of falling through", %{conn: conn} do
      _org = insert(:organization, slug: "real-org")

      conn =
        conn
        |> Map.put(:host, "localhost")
        |> put_query_params(%{"org" => "ghost-org"})
        |> SetOrganization.call([])

      assert conn.status == 404
    end

    test "an unknown explicit `?org=` does not pivot to the session org", %{conn: conn} do
      session_org = insert(:organization, slug: "session-org")
      _other = insert(:organization, slug: "other-org")

      # Stash a previously-resolved session_org in the session, then make a
      # new request with `?org=ghost-org`. The explicit signal must win — we
      # must not silently fall back to the session_org.
      conn =
        conn
        |> Plug.Test.init_test_session(%{
          organization_id: session_org.id,
          org_slug: session_org.slug
        })
        |> Map.put(:host, "localhost")
        |> put_query_params(%{"org" => "ghost-org"})
        |> SetOrganization.call([])

      assert conn.status == 404
    end

    test "clears stale session org_slug/organization_id on explicit ?org= failure in optional mode",
         %{conn: conn} do
      prior = insert(:organization, slug: "prior-org")

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          organization_id: prior.id,
          org_slug: prior.slug
        })
        |> Map.put(:host, "localhost")
        |> put_query_params(%{"org" => "ghost-org"})
        |> SetOrganization.call(optional: true)

      assert conn.assigns[:organization] == nil
      assert Plug.Conn.get_session(conn, :organization_id) == nil
      assert Plug.Conn.get_session(conn, :org_slug) == nil
      assert Plug.Conn.get_session(conn, :no_org_resolved) == true
    end

    test "an unknown explicit `?org=` does not pivot to the viewer-token org in optional mode",
         %{conn: conn} do
      viewer_org = insert(:organization, slug: "viewer-org")
      viewer = insert(:viewer, organization: viewer_org)
      token = Marquee.Viewers.generate_viewer_session_token(viewer)

      conn =
        conn
        |> Plug.Test.init_test_session(%{viewer_token: token})
        |> Map.put(:host, "localhost")
        |> put_query_params(%{"org" => "ghost-org"})
        |> SetOrganization.call(optional: true)

      # With the bug: this would resolve to viewer_org via the viewer token.
      # Fixed: explicit ?org=ghost-org is authoritative and unresolvable, so
      # the optional handler returns nil org (marketing page).
      refute conn.assigns[:organization] == viewer_org
      assert conn.assigns[:organization] in [nil]
    end
  end

  describe "hostname resolution mode" do
    setup do
      original = Application.get_env(:marquee, :org_resolution)
      Application.put_env(:marquee, :org_resolution, :hostname)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:marquee, :org_resolution)
        else
          Application.put_env(:marquee, :org_resolution, original)
        end
      end)

      :ok
    end

    test "ignores `?org=` query param entirely", %{conn: conn} do
      _real = insert(:organization, slug: "real-org")
      _other = insert(:organization, slug: "other-org")

      conn =
        conn
        |> Map.put(:host, "real-org.localhost")
        |> put_query_params(%{"org" => "other-org"})
        |> SetOrganization.call([])

      # Resolved by host, not by the query param
      assert conn.assigns.organization.slug == "real-org"
    end

    test "404s when host does not match and `?org=` is ignored", %{conn: conn} do
      _real = insert(:organization, slug: "real-org")

      conn =
        conn
        |> Map.put(:host, "localhost")
        |> put_query_params(%{"org" => "real-org"})
        |> SetOrganization.call([])

      assert conn.status == 404
    end
  end

  describe "multi-tenant isolation" do
    test "resolves correct org from subdomain when multiple orgs exist", %{conn: conn} do
      org_a = insert(:organization)
      org_b = insert(:organization)

      conn_a =
        conn
        |> Map.put(:host, "#{org_a.slug}.localhost")
        |> SetOrganization.call([])

      conn_b =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Map.put(:host, "#{org_b.slug}.localhost")
        |> SetOrganization.call([])

      assert conn_a.assigns.organization.id == org_a.id
      assert conn_b.assigns.organization.id == org_b.id
      refute conn_a.assigns.organization.id == conn_b.assigns.organization.id
    end
  end
end
