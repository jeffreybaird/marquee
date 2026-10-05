defmodule MarqueeWeb.Viewer.PlatformHomeSessionTest do
  use MarqueeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Marquee.{Repo, SubscriberDemo, TenantDomains, Viewers}

  @platform "marquee.jeffreybaird.com"
  @pattern "{slug}-marquee.jeffreybaird.com"

  setup do
    endpoint = Application.fetch_env!(:marquee, MarqueeWeb.Endpoint)

    changes = [
      {:org_resolution, :query_param},
      {:tenant_host_pattern, @pattern},
      {:tenant_domain_provisioning,
       [
         enabled: true,
         zone: "jeffreybaird.com",
         account_id: "123",
         api_token: "fixture",
         target_ipv4: "192.0.2.25",
         host_pattern: @pattern
       ]},
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

    %{org: insert(:organization, name: "Previous tenant")}
  end

  test "bare platform home drops passive tenant bridge in HTTP and connected LiveView", %{
    org: org
  } do
    tenant = platform_conn() |> get("/?org=#{org.slug}")
    assert html_response(tenant, 200) =~ org.name
    assert get_session(tenant, :organization_id) == org.id
    platform = recycle(tenant) |> get("/")
    assert_platform(platform)
    assert get_session(platform, :organization_id) == nil
    assert get_session(platform, :org_slug) == nil
    assert get_session(platform, :no_org_resolved) == true
  end

  test "demo and ordinary viewer tokens survive bare platform home without selecting their tenant",
       %{org: org} do
    demo_org = insert(:organization, features: %{"subscriber_demo" => true})
    insert(:video, organization: demo_org, published: true, mux_status: "ready")
    {:ok, demo} = SubscriberDemo.start_session(demo_org)
    viewer = insert(:subscribed_viewer, organization: org)
    ordinary_token = Viewers.generate_viewer_session_token(viewer)

    for {owner, token, viewer_id} <- [
          {demo_org, demo.token, demo.viewer.id},
          {org, ordinary_token, viewer.id}
        ] do
      conn =
        platform_conn()
        |> init_test_session(%{
          organization_id: owner.id,
          org_slug: owner.slug,
          viewer_token: token
        })
        |> get("/")

      assert_platform(conn)
      assert get_session(conn, :viewer_token) == token
      assert Viewers.get_viewer_by_session_token(token).id == viewer_id
      assert get_session(conn, :organization_id) == nil
      assert get_session(conn, :org_slug) == nil
    end
  end

  test "HEAD and empty explicit signals do not recover passive platform tenant", %{org: org} do
    conn =
      platform_conn()
      |> init_test_session(%{organization_id: org.id, org_slug: org.slug})
      |> head("/")

    assert response(conn, 200)
    assert conn.assigns[:organization] == nil
    assert get_session(conn, :organization_id) == nil

    conn =
      platform_conn()
      |> init_test_session(%{organization_id: org.id, org_slug: org.slug})
      |> put_req_header("x-marquee-org", "")
      |> get("/?org=")

    assert_platform(conn)
  end

  test "configured localhost platform also ignores a remembered organization", %{org: org} do
    endpoint = Application.fetch_env!(:marquee, MarqueeWeb.Endpoint)

    Application.put_env(
      :marquee,
      MarqueeWeb.Endpoint,
      Keyword.put(endpoint, :url, host: "localhost", scheme: "http", port: 4002)
    )

    conn =
      build_conn()
      |> Map.put(:host, "localhost")
      |> init_test_session(%{organization_id: org.id, org_slug: org.slug})
      |> get("/")

    assert_platform(conn)
  end

  test "explicit pending tenant signals and nonroot continuation retain tenant selection", %{
    org: org
  } do
    for conn <- [
          platform_conn() |> get("/?org=#{org.slug}"),
          platform_conn() |> put_req_header("x-marquee-org", org.slug) |> get("/")
        ] do
      assert html_response(conn, 200) =~ org.name
      assert get_session(conn, :organization_id) == org.id
      assert {:ok, _view, html} = live(conn)
      refute html =~ ~s(data-test="platform-marketing")
      continuation = recycle(conn) |> delete_req_header("x-marquee-org") |> get("/login")
      assert html_response(continuation, 200) =~ org.name
    end
  end

  test "ready tenant hosts ignore stale platform flag and explicit legacy links still canonicalize",
       %{org: org} do
    {:ok, domain} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        TenantDomains.request_provisioning(org, source: :backend)
      end)

    domain =
      Repo.update!(
        Ecto.Changeset.change(domain,
          status: :ready,
          dns_record_id: "123",
          ready_at: DateTime.utc_now()
        )
      )

    conn = platform_conn() |> get("/?org=#{org.slug}")
    assert redirected_to(conn) == "https://#{domain.hostname}/"

    tenant =
      build_conn()
      |> Map.put(:host, domain.hostname)
      |> init_test_session(%{no_org_resolved: true})
      |> get("/")

    assert html_response(tenant, 200) =~ org.name
    assert {:ok, _view, html} = live(tenant)
    refute html =~ ~s(data-test="platform-marketing")
  end

  test "authenticated operator redirect and authorized preview are not turned into marketing", %{
    org: org
  } do
    member = insert(:membership, organization: org, role: :owner)
    conn = conn_for(member) |> Map.put(:host, @platform) |> get("/")
    assert redirected_to(conn) =~ "/admin"

    preview =
      conn_for(member) |> Map.put(:host, @platform) |> get("/?org=#{org.slug}&preview=member")

    assert html_response(preview, 200) =~ "Member preview"
    continued = recycle(preview) |> get("/")
    assert html_response(continued, 200) =~ "Member preview"
    assert {:ok, _view, html} = live(continued)
    refute html =~ ~s(data-test="platform-marketing")
  end

  defp platform_conn, do: build_conn() |> Map.put(:host, @platform)

  defp assert_platform(conn) do
    html = html_response(conn, 200)
    assert html =~ ~s(data-test="platform-marketing")
    assert conn.assigns[:organization] == nil
    assert {:ok, view, connected} = live(conn)
    assert has_element?(view, "[data-test=platform-marketing]")
    assert connected =~ ~s(data-test="marketing-headline")
    refute has_element?(view, "[data-test=subscriber-demo-banner]")
  end
end
