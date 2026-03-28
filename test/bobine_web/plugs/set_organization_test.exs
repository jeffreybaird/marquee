defmodule BobineWeb.Plugs.SetOrganizationTest do
  use BobineWeb.ConnCase, async: true

  alias BobineWeb.Plugs.SetOrganization
  alias Bobine.Accounts.Scope

  setup %{conn: conn} do
    {:ok, conn: Plug.Test.init_test_session(conn, %{})}
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
