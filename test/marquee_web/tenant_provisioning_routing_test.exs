defmodule MarqueeWeb.TenantProvisioningRoutingTest do
  use MarqueeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Marquee.TenantDomains
  alias Marquee.TenantDomains.ScriptedClients
  alias Marquee.Viewers.ViewerNotifier
  alias MarqueeWeb.OrgURL

  @platform "marquee.jeffreybaird.com"
  @pattern "{slug}-marquee.jeffreybaird.com"

  setup do
    endpoint = Application.fetch_env!(:marquee, MarqueeWeb.Endpoint)

    changes = [
      {:tenant_domain_provisioning,
       [
         enabled: true,
         zone: "jeffreybaird.com",
         account_id: "123",
         api_token: "test-token",
         target_ipv4: "192.0.2.25",
         host_pattern: @pattern
       ]},
      {:tenant_host_pattern, @pattern},
      {:org_resolution, :hostname},
      {:tenant_dns_client, Marquee.TenantDomains.ScriptedDNSClient},
      {:tenant_hostname_probe, Marquee.TenantDomains.ScriptedProbe},
      {MarqueeWeb.Endpoint,
       Keyword.put(endpoint, :url, host: @platform, scheme: "https", port: 443)}
    ]

    original = Map.new(changes, fn {key, _} -> {key, Application.fetch_env(:marquee, key)} end)
    for {key, value} <- changes, do: Application.put_env(:marquee, key, value)

    on_exit(fn ->
      for {key, value} <- original do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end
    end)

    start_supervised!(ScriptedClients)
    %{org: insert(:organization, name: "Pending studio")}
  end

  test "unenrolled pending and failed tenants retain legacy viewer HTTP and connected login", %{
    org: org
  } do
    assert_legacy_login(org)
    domain = enroll(org)
    assert_legacy_login(org)

    Marquee.Repo.update!(
      Ecto.Changeset.change(domain, status: :failed, last_error: "dns_conflict")
    )

    assert_legacy_login(org)
    assert ScriptedClients.calls() == []
  end

  test "pending tenant URL generation preserves org for external links and relative paths", %{
    org: org
  } do
    enroll(org)

    assert OrgURL.org_url("https://#{@platform}/checkout?session_id=abc", org) ==
             "https://#{@platform}/checkout?org=#{org.slug}&session_id=abc"

    assert OrgURL.org_url("/admin/settings/billing", org) ==
             "/admin/settings/billing?org=#{org.slug}"

    viewer = insert(:viewer, organization: org)

    assert {:ok, email} =
             ViewerNotifier.deliver_magic_link(viewer, "test-token", org)

    assert email.text_body =~ "https://#{@platform}/magic-link/test-token?org=#{org.slug}"
  end

  test "pending tenant admin keeps explicit org through HTTP and socket instead of another primary membership",
       %{org: org} do
    enroll(org)
    user = insert(:user)
    other = insert(:organization, name: "Other studio")
    insert(:membership, user: user, organization: other, inserted_at: ~U[2020-01-01 00:00:00Z])
    member = insert(:membership, user: user, organization: org, role: :owner)
    conn = conn_for(member) |> Map.put(:host, @platform)
    assert {:ok, view, html} = live(conn, "/admin?org=#{org.slug}")
    assert html =~ org.name
    refute html =~ other.name
    assert has_element?(view, "[data-test=admin-view-site][href*='org=#{org.slug}']")
  end

  test "ready tenant redirects legacy links and keeps its persisted host after slug change", %{
    org: org
  } do
    domain = enroll(org) |> ready()

    for mode <- [:hostname, :query_param] do
      Application.put_env(:marquee, :org_resolution, mode)
      conn = host_conn(@platform) |> get("/login?org=#{org.slug}&ref=email")
      assert redirected_to(conn) == "https://#{domain.hostname}/login?ref=email"
      assert {:ok, _view, html} = live(host_conn(domain.hostname), "/login")
      assert html =~ org.name
    end

    renamed = Marquee.Repo.update!(Ecto.Changeset.change(org, slug: "renamed-studio"))

    assert OrgURL.org_url("https://#{@platform}/login", renamed) ==
             "https://#{domain.hostname}/login"

    assert {:ok, _view, html} = live(host_conn(domain.hostname), "/login")
    assert html =~ org.name
  end

  test "DNS-ready host exposes only its readiness identity and cannot serve tenant login", %{
    org: org
  } do
    domain = enroll(org)

    domain =
      Marquee.Repo.update!(
        Ecto.Changeset.change(domain, status: :dns_ready, dns_record_id: "123")
      )

    conn = host_conn(domain.hostname) |> get("/.well-known/marquee-domain")

    assert json_response(conn, 200) == %{
             "hostname" => domain.hostname,
             "domain_id" => domain.id,
             "generation" => domain.generation
           }

    conn = host_conn(domain.hostname) |> get("/login")
    assert response(conn, 404)
    refute conn.resp_body =~ org.name
    conn = host_conn("unknown-marquee.jeffreybaird.com") |> get("/.well-known/marquee-domain")
    assert response(conn, 404)
    assert ScriptedClients.calls() == []
  end

  test "ready host is authoritative over every legacy tenant signal in both global modes", %{
    org: org
  } do
    domain = enroll(org) |> ready()
    other = insert(:organization, name: "Other studio")

    for mode <- [:query_param, :hostname] do
      Application.put_env(:marquee, :org_resolution, mode)

      conn =
        host_conn(domain.hostname)
        |> init_test_session(%{organization_id: other.id, org_slug: other.slug})
        |> put_req_header("x-marquee-org", other.slug)

      assert {:ok, _view, html} = live(conn, "/login?org=#{other.slug}")
      assert html =~ org.name
      refute html =~ other.name
    end
  end

  test "unknown and pending host cannot use platform legacy tenant signals", %{org: org} do
    domain = enroll(org)

    for mode <- [:query_param, :hostname],
        host <- [domain.hostname, "unknown-marquee.jeffreybaird.com", "foreign.example"] do
      Application.put_env(:marquee, :org_resolution, mode)

      conn =
        host_conn(host)
        |> init_test_session(%{organization_id: org.id, org_slug: org.slug})
        |> put_req_header("x-marquee-org", org.slug)
        |> get("/login?org=#{org.slug}")

      assert response(conn, 404)
      refute conn.resp_body =~ org.name
    end
  end

  test "certificate ask authorizes persisted DNS-ready hosts and fails closed without provider work",
       %{org: org} do
    domain = enroll(org)

    assert host_conn(@platform)
           |> get("/internal/tenant-domains/ask", domain: domain.hostname)
           |> response(403)

    domain =
      Marquee.Repo.update!(
        Ecto.Changeset.change(domain, status: :dns_ready, dns_record_id: "123")
      )

    assert host_conn(@platform)
           |> get("/internal/tenant-domains/ask", domain: domain.hostname)
           |> response(200)

    for hostname <- [
          "unknown-marquee.jeffreybaird.com",
          "#{domain.hostname}.evil.example",
          "custom.example",
          @platform
        ] do
      assert host_conn(@platform)
             |> get("/internal/tenant-domains/ask", domain: hostname)
             |> response(403)
    end

    Marquee.Repo.update!(
      Ecto.Changeset.change(org, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    )

    assert host_conn(@platform)
           |> get("/internal/tenant-domains/ask", domain: domain.hostname)
           |> response(403)

    assert host_conn(domain.hostname) |> get("/.well-known/marquee-domain") |> response(404)
    assert ScriptedClients.calls() == []
  end

  test "automatic ready tenant operator magic link stays on requested tenant in query mode", %{
    org: org
  } do
    Application.put_env(:marquee, :org_resolution, :query_param)
    domain = enroll(org) |> ready()
    user = insert(:user)
    primary = insert(:organization)
    insert(:membership, user: user, organization: primary, inserted_at: ~U[2020-01-01 00:00:00Z])
    insert(:membership, user: user, organization: org)
    assert {:ok, view, _} = live(host_conn(domain.hostname), "/users/log-in")
    view |> form("#login_form_magic", user: %{email: user.email}) |> render_submit()

    assert_email_sent(fn email ->
      assert email.text_body =~ "https://#{domain.hostname}/users/log-in/"
      refute email.text_body =~ "org=#{primary.slug}"
      refute email.text_body =~ "?org="
      true
    end)
  end

  test "automatic ready tenant settings confirmation stays on its authenticated host in query mode",
       %{org: org} do
    Application.put_env(:marquee, :org_resolution, :query_param)
    domain = enroll(org) |> ready()
    member = insert(:membership, organization: org, role: :owner)
    conn = conn_for(member) |> Map.put(:host, domain.hostname)
    assert {:ok, view, _} = live(conn, "/users/settings")

    view
    |> form("#email_form",
      user: %{email: "changed-#{System.unique_integer([:positive])}@example.com"}
    )
    |> render_submit()

    assert_email_sent(fn email ->
      assert email.text_body =~ "https://#{domain.hostname}/users/settings/confirm-email/"
      refute email.text_body =~ "?org="
      true
    end)
  end

  test "automatic ready tenant platform operator preview is canonical in query mode", %{org: org} do
    Application.put_env(:marquee, :org_resolution, :query_param)
    domain = enroll(org) |> ready()
    member = insert(:membership, organization: org, role: :owner)
    conn = conn_for(member) |> Map.put(:host, @platform)
    assert {:ok, view, _} = live(conn, "/admin")

    assert has_element?(
             view,
             "[data-test=admin-view-site][href='https://#{domain.hostname}/?preview=member']"
           )
  end

  test "subscriber demo discovery changes from legacy to canonical only when ready in query mode",
       %{org: org} do
    Application.put_env(:marquee, :org_resolution, :query_param)
    org = Marquee.Repo.update!(Ecto.Changeset.change(org, features: %{"subscriber_demo" => true}))
    domain = enroll(org)
    assert {:ok, pending_view, _} = live(host_conn(@platform), "/")

    assert has_element?(
             pending_view,
             "[data-test=subscriber-demo-entry][href*='org=#{org.slug}']"
           )

    domain = ready(domain)
    assert {:ok, ready_view, _} = live(host_conn(@platform), "/")

    assert has_element?(
             ready_view,
             "[data-test=subscriber-demo-entry][href='https://#{domain.hostname}/']"
           )
  end

  defp assert_legacy_login(org) do
    for mode <- [:hostname, :query_param] do
      Application.put_env(:marquee, :org_resolution, mode)
      assert {:ok, view, html} = live(host_conn(@platform), "/login?org=#{org.slug}")
      assert html =~ org.name
      assert has_element?(view, "[data-test=login-form]")
    end
  end

  defp enroll(org) do
    {:ok, domain} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        TenantDomains.request_provisioning(org, source: :backend)
      end)

    domain
  end

  defp ready(domain),
    do:
      Marquee.Repo.update!(
        Ecto.Changeset.change(domain,
          status: :ready,
          dns_record_id: "123",
          ready_at: DateTime.utc_now()
        )
      )

  defp host_conn(host), do: build_conn() |> Map.put(:host, host)
end
