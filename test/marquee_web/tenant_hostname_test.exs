defmodule MarqueeWeb.TenantHostnameTest do
  use MarqueeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Marquee.Accounts.Scope
  alias Marquee.Viewers.ViewerNotifier
  alias MarqueeWeb.Hooks.AssignScope
  alias MarqueeWeb.OrgURL
  alias MarqueeWeb.Plugs.SetOrganization

  setup do
    keys = [:org_resolution, :tenant_host_pattern, MarqueeWeb.Endpoint]
    original = Map.new(keys, &{&1, Application.fetch_env(:marquee, &1)})
    Application.put_env(:marquee, :org_resolution, :hostname)
    Application.put_env(:marquee, :tenant_host_pattern, "{slug}-marquee.jeffreybaird.com")
    endpoint = Application.fetch_env!(:marquee, MarqueeWeb.Endpoint)

    Application.put_env(
      :marquee,
      MarqueeWeb.Endpoint,
      Keyword.put(endpoint, :url, host: "marquee.jeffreybaird.com", scheme: "https", port: 443)
    )

    on_exit(fn ->
      for {key, value} <- original do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end
    end)

    %{org: insert(:organization, slug: "the-workshop", name: "Workshop studio")}
  end

  test "configured host resolves unchanged hyphenated slug, ignoring other tenant signals", %{
    org: org
  } do
    other = insert(:organization)

    conn =
      tenant_conn("#{org.slug}-marquee.jeffreybaird.com", "/?org=#{other.slug}")
      |> put_session(:organization_id, other.id)
      |> put_session(:org_slug, other.slug)
      |> put_req_header("x-marquee-org", other.slug)
      |> SetOrganization.call([])

    assert conn.assigns.organization.id == org.id
    assert get_session(conn, :organization_id) == org.id
  end

  test "custom domain remains authoritative", %{org: org} do
    custom = insert(:organization, custom_domain: "#{org.slug}-marquee.jeffreybaird.com")
    conn = tenant_conn(custom.custom_domain) |> SetOrganization.call([])
    assert conn.assigns.organization.id == custom.id
  end

  test "legacy operator magic link redirects through the browser pipeline before token consumption",
       %{
         org: org
       } do
    user = insert(:user)
    insert(:membership, user: user, organization: org)
    {token, _hashed_token} = Marquee.AccountsFixtures.generate_user_magic_link_token(user)

    conn =
      build_conn()
      |> Map.put(:host, "marquee.jeffreybaird.com")
      |> get("/users/log-in/#{token}?org=#{org.slug}&ref=email")

    assert redirected_to(conn, 302) ==
             "https://#{org.slug}-marquee.jeffreybaird.com/users/log-in/#{token}?ref=email"

    assert Marquee.Accounts.get_user_by_magic_link_token(token).id == user.id
    assert get_session(conn, :user_token) == nil
  end

  test "foreign, partial, unknown and platform hosts cannot recover tenant from session or membership",
       %{org: org} do
    user = insert(:user)
    insert(:membership, user: user, organization: org)
    viewer = insert(:viewer, organization: org)
    token = Marquee.Viewers.generate_viewer_session_token(viewer)

    for host <- [
          "#{org.slug}.attacker.example",
          "#{org.slug}-marquee.jeffreybaird.com.attacker.example",
          "nested.#{org.slug}-marquee.jeffreybaird.com",
          "missing-marquee.jeffreybaird.com"
        ] do
      conn =
        tenant_conn(host)
        |> put_session(:organization_id, org.id)
        |> put_session(:org_slug, org.slug)
        |> put_session(:viewer_token, token)
        |> assign(:current_scope, Scope.for_user(user))
        |> SetOrganization.call([])

      assert conn.status == 404, host
      assert conn.halted
    end

    conn =
      tenant_conn("marquee.jeffreybaird.com")
      |> put_session(:viewer_token, token)
      |> put_session(:organization_id, org.id)
      |> SetOrganization.call(optional: true)

    assert conn.assigns[:organization] == nil
  end

  test "legacy GET and HEAD redirect only from platform with remaining query intact", %{org: org} do
    for method <- [:get, :head] do
      conn =
        tenant_conn(
          "marquee.jeffreybaird.com",
          "/login?org=#{org.slug}&ref=email&next=%2Fbrowse",
          method
        )
        |> SetOrganization.call([])

      assert conn.status == 302
      assert conn.halted
      [location] = get_resp_header(conn, "location")
      uri = URI.parse(location)
      assert uri.scheme == "https"
      assert uri.host == "the-workshop-marquee.jeffreybaird.com"
      assert uri.path == "/login"
      assert URI.decode_query(uri.query) == %{"ref" => "email", "next" => "/browse"}
    end
  end

  test "legacy unknown tenants, POSTs and foreign hosts never redirect", %{org: org} do
    for {host, slug, method} <- [
          {"marquee.jeffreybaird.com", "missing", :get},
          {"marquee.jeffreybaird.com", org.slug, :post},
          {"attacker.example", org.slug, :get}
        ] do
      conn = tenant_conn(host, "/login?org=#{slug}", method) |> SetOrganization.call([])
      assert conn.status == 404
      assert get_resp_header(conn, "location") == []
    end
  end

  test "LiveView mount uses the same host boundary and ignores stale session and impersonation",
       %{org: org} do
    other = insert(:organization)
    session = %{"organization_id" => other.id, "impersonated_org_id" => other.id}

    socket = %Phoenix.LiveView.Socket{
      host_uri: URI.parse("https://#{org.slug}-marquee.jeffreybaird.com"),
      assigns: %{__changed__: %{}}
    }

    assert {:cont, mounted} = AssignScope.on_mount(:assign_org, %{}, session, socket)
    assert mounted.assigns.organization.id == org.id

    socket = %{socket | host_uri: URI.parse("https://#{org.slug}.attacker.example")}
    assert {:cont, mounted} = AssignScope.on_mount(:assign_org, %{}, session, socket)
    assert mounted.assigns.organization == nil
  end

  test "connected viewer login retains host tenant and clean navigation", %{org: org} do
    other = insert(:organization, name: "Other studio")
    conn = build_conn() |> Map.put(:host, "#{org.slug}-marquee.jeffreybaird.com")
    assert {:ok, view, html} = live(conn, "/login?org=#{other.slug}")
    assert html =~ org.name
    refute html =~ other.name
    assert has_element?(view, "[data-test=login-register-link][href='/register']")

    assert view
           |> element("[data-test=login-form]")
           |> render_submit(%{email: "absent@example.com"}) =~ "Check your email"
  end

  test "super admin impersonation is limited to platform host in both HTTP and LiveView", %{
    org: org
  } do
    other = insert(:organization)
    user = insert(:user, is_super_admin: true)
    token = Marquee.Accounts.generate_user_session_token(user)

    for {host, expected} <- [
          {"marquee.jeffreybaird.com", other},
          {"#{org.slug}-marquee.jeffreybaird.com", org}
        ] do
      conn =
        tenant_conn(host)
        |> assign(:current_scope, Scope.for_user(user))
        |> put_session(:impersonated_org_id, other.id)
        |> SetOrganization.call([])

      assert conn.assigns.current_scope.organization.id == expected.id

      socket = %Phoenix.LiveView.Socket{
        host_uri: URI.parse("https://#{host}"),
        assigns: %{__changed__: %{}}
      }

      session = %{"user_token" => token, "impersonated_org_id" => other.id}
      assert {:cont, mounted} = AssignScope.on_mount(:assign_org, %{}, session, socket)
      assert mounted.assigns.organization.id == expected.id
    end
  end

  test "connected admin resolves host membership and rejects another tenant's operator", %{
    org: org
  } do
    member = insert(:membership, organization: org, role: :owner)
    conn = conn_for(member) |> Map.put(:host, "#{org.slug}-marquee.jeffreybaird.com")
    assert {:ok, _view, html} = live(conn, "/admin")
    assert html =~ org.name

    other_member = insert(:membership, role: :owner)
    conn = conn_for(other_member) |> Map.put(:host, "#{org.slug}-marquee.jeffreybaird.com")
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin")
  end

  test "platform operator admin keeps authenticated membership fallback", %{org: org} do
    member = insert(:membership, organization: org, role: :owner)
    conn = conn_for(member) |> Map.put(:host, "marquee.jeffreybaird.com")
    assert {:ok, _view, html} = live(conn, "/admin")
    assert html =~ org.name
  end

  test "platform operator view-site link reaches the canonical tenant", %{org: org} do
    member = insert(:membership, organization: org, role: :owner)
    conn = conn_for(member) |> Map.put(:host, "marquee.jeffreybaird.com")
    assert {:ok, view, _html} = live(conn, "/admin")

    assert has_element?(
             view,
             "[data-test=admin-view-site][href='https://#{org.slug}-marquee.jeffreybaird.com/?preview=member']"
           )
  end

  test "platform super admin view-site link retains its impersonation session", %{org: org} do
    user = insert(:user, is_super_admin: true)

    conn =
      conn_for_super_admin(user)
      |> Map.put(:host, "marquee.jeffreybaird.com")
      |> put_session(:impersonated_org_id, org.id)

    assert {:ok, view, _html} = live(conn, "/admin")
    assert has_element?(view, "[data-test=admin-view-site][href='/?preview=member']")
  end

  test "stale marketing-page flag cannot suppress a valid hostname tenant", %{org: org} do
    socket = %Phoenix.LiveView.Socket{
      host_uri: URI.parse("https://#{org.slug}-marquee.jeffreybaird.com"),
      assigns: %{__changed__: %{}}
    }

    assert {:cont, mounted} =
             AssignScope.on_mount(:assign_org, %{}, %{"no_org_resolved" => true}, socket)

    assert mounted.assigns.organization.id == org.id
  end

  test "external URLs replace platform host and remove org while preserving path query and fragment",
       %{org: org} do
    uri =
      OrgURL.org_url(
        "https://marquee.jeffreybaird.com/checkout?org=stale&session_id=abc#done",
        org
      )
      |> URI.parse()

    assert uri.host == "the-workshop-marquee.jeffreybaird.com"
    assert uri.path == "/checkout"
    assert uri.fragment == "done"
    assert URI.decode_query(uri.query) == %{"session_id" => "abc"}

    assert OrgURL.org_url("https://marquee.jeffreybaird.com/login", %{
             org
             | custom_domain: "watch.example.com"
           }) == "https://watch.example.com/login"
  end

  test "viewer magic link email uses canonical tenant hostname", %{org: org} do
    viewer = insert(:viewer, organization: org)

    assert {:ok, email} =
             ViewerNotifier.deliver_magic_link(viewer, "test-token", org)

    assert email.text_body =~
             "https://the-workshop-marquee.jeffreybaird.com/magic-link/test-token"

    refute email.text_body =~ "?org="
  end

  test "relative tenant paths stay relative and drop organization query", %{org: org} do
    assert OrgURL.org_url("/login?org=stale&next=browse", org) == "/login?next=browse"
  end

  test "operator magic email uses requested tenant instead of primary membership", %{org: org} do
    user = insert(:user)
    primary = insert(:organization)
    insert(:membership, user: user, organization: primary, inserted_at: ~U[2020-01-01 00:00:00Z])
    insert(:membership, user: user, organization: org)
    conn = build_conn() |> Map.put(:host, "#{org.slug}-marquee.jeffreybaird.com")
    assert {:ok, view, _html} = live(conn, "/users/log-in")
    view |> form("#login_form_magic", user: %{email: user.email}) |> render_submit()

    assert_email_sent(fn email ->
      assert email.text_body =~ "https://#{org.slug}-marquee.jeffreybaird.com/users/log-in/"
      refute email.text_body =~ "#{primary.slug}-marquee"
      refute email.text_body =~ "?org="
      true
    end)
  end

  test "development query mode remains available even with host pattern configured", %{org: org} do
    Application.put_env(:marquee, :org_resolution, :query_param)
    conn = tenant_conn("localhost", "/?org=#{org.slug}") |> SetOrganization.call([])
    assert conn.assigns.organization.id == org.id
    refute conn.halted

    assert OrgURL.org_url("http://localhost:4000/login", org) ==
             "http://localhost:4000/login?org=#{org.slug}"
  end

  test "operator email confirmation returns to the tenant holding the authenticated session", %{
    org: org
  } do
    member = insert(:membership, organization: org, role: :owner)
    conn = conn_for(member) |> Map.put(:host, "#{org.slug}-marquee.jeffreybaird.com")
    new_email = "updated-#{System.unique_integer([:positive])}@example.com"
    assert {:ok, view, _html} = live(conn, "/users/settings")

    assert view
           |> form("#email_form", user: %{email: new_email})
           |> render_submit() =~ "A link to confirm your email"

    assert_email_sent(fn email ->
      assert email.to == [{"", new_email}]

      assert email.text_body =~
               "https://#{org.slug}-marquee.jeffreybaird.com/users/settings/confirm-email/"

      refute email.text_body =~ "https://marquee.jeffreybaird.com/users/settings/confirm-email/"
      refute email.text_body =~ "?org="
      true
    end)
  end

  defp tenant_conn(host, path \\ "/", method \\ :get) do
    Plug.Test.conn(method, path)
    |> Map.put(:host, host)
    |> Plug.Test.init_test_session(%{})
  end
end
