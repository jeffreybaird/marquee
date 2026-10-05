defmodule MarqueeWeb.Viewer.SubscriberDemoColdEntryTest do
  use MarqueeWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Marquee.{Engagement, Repo, SubscriberDemo, TenantDomains, Viewers}
  alias Marquee.LandingPage.LandingSection
  alias Marquee.Viewers.{Viewer, ViewerToken}
  alias MarqueeWeb.Plugs.RateLimit

  setup do
    pattern = "{slug}-marquee.jeffreybaird.com"

    changes = [
      subscriber_demo_catalog: Marquee.SubscriberDemoFixtures.catalog_manifest(),
      org_resolution: :query_param,
      tenant_host_pattern: pattern,
      rate_limit_disabled: true,
      tenant_domain_provisioning: [
        enabled: true,
        zone: "jeffreybaird.com",
        account_id: "123",
        api_token: "fixture",
        target_ipv4: "192.0.2.25",
        host_pattern: pattern
      ]
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

      RateLimit.reset()
    end)

    org = insert(:organization, features: %{"subscriber_demo" => true})
    {:ok, catalog} = SubscriberDemo.seed_catalog(org)

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

    %{org: org, catalog: catalog, host: domain.hostname}
  end

  test "fresh ready-host GET renders themed landing without allocation and explicit POST enters catalog",
       %{org: org, catalog: catalog, host: host} do
    section_count = Repo.aggregate(LandingSection, :count)
    conn = host_conn(host) |> get("/")
    html = html_response(conn, 200)
    assert html =~ ~s(data-test="subscriber-demo-landing")
    refute html =~ ~s(data-test="subscriber-demo-banner")
    assert html =~ "Begin demo"
    refute get_session(conn, :viewer_token)
    assert demo_count(org) == 0
    assert Repo.aggregate(ViewerToken, :count) == 0
    assert Repo.aggregate(LandingSection, :count) == section_count
    assert {:ok, view, _} = live(conn)
    assert has_element?(view, "[data-test=subscriber-demo-entry][data-method=post]", "Begin demo")
    assert demo_count(org) == 0
    assert Repo.aggregate(ViewerToken, :count) == 0
    assert Repo.aggregate(LandingSection, :count) == section_count

    started = recycle(conn) |> post("/demo/subscriber")
    assert redirected_to(started) == "/"
    assert_no_store(started)
    viewer = session_viewer(started)
    assert SubscriberDemo.demo_viewer?(viewer)
    assert viewer.organization_id == org.id
    refute SubscriberDemo.expired?(viewer)
    assert demo_count(org) == 1
    assert {:ok, catalog_view, _} = live(recycle(started), "/")
    assert has_element?(catalog_view, "[data-test=subscriber-demo-banner]")

    assert has_element?(
             catalog_view,
             "[data-test=hero-primary-cta-0][href='/watch/#{hd(catalog.videos).id}']"
           )

    repeated = recycle(started) |> get("/")
    assert session_viewer(repeated).id == viewer.id
    reused = recycle(repeated) |> post("/demo/subscriber")
    assert session_viewer(reused).id == viewer.id
    assert demo_count(org) == 1
  end

  test "two browsers explicitly start isolated identities and engagement", %{
    org: org,
    catalog: catalog,
    host: host
  } do
    first = host_conn(host) |> post("/demo/subscriber") |> session_viewer()
    second = host_conn(host) |> post("/demo/subscriber") |> session_viewer()
    assert first.id != second.id
    video = hd(catalog.videos)
    assert {:ok, _} = Engagement.add_to_watchlist(org, first, video)
    assert Engagement.in_watchlist?(org, first, video)
    refute Engagement.in_watchlist?(org, second, video)
  end

  test "expired and wrong-tenant demo tokens require explicit POST before a new identity", %{
    org: org,
    host: host
  } do
    {:ok, expired} = SubscriberDemo.start_session(org)
    past = DateTime.utc_now() |> DateTime.add(-60) |> DateTime.to_iso8601()

    Repo.update!(
      Ecto.Changeset.change(expired.viewer,
        metadata: Map.put(expired.viewer.metadata, "subscriber_demo_expires_at", past)
      )
    )

    other = insert(:organization, features: %{"subscriber_demo" => true})
    insert(:video, organization: other, published: true, mux_status: "ready")
    {:ok, foreign} = SubscriberDemo.start_session(other)

    for stale <- [expired, foreign] do
      conn = host_conn(host) |> init_test_session(%{viewer_token: stale.token}) |> get("/")
      assert html_response(conn, 200) =~ ~s(data-test="subscriber-demo-entry")
      assert get_session(conn, :viewer_token) == stale.token
      renewed = conn |> recycle() |> post("/demo/subscriber") |> session_viewer()
      assert renewed.organization_id == org.id
      assert renewed.id != stale.viewer.id
      assert SubscriberDemo.demo_viewer?(renewed)
    end

    assert Viewers.get_viewer_by_session_token(foreign.token).id == foreign.viewer.id
  end

  test "ordinary viewer tokens from either tenant are never replaced by demos", %{
    org: org,
    host: host
  } do
    for owner <- [org, insert(:organization)] do
      viewer = insert(:subscribed_viewer, organization: owner)
      token = Viewers.generate_viewer_session_token(viewer)
      conn = host_conn(host) |> init_test_session(%{viewer_token: token}) |> get("/")
      assert get_session(conn, :viewer_token) == token
      assert Viewers.get_viewer_by_session_token(token).id == viewer.id
      assert demo_count(org) == 0
    end
  end

  test "operator, member preview and viewer impersonation keep their existing identity", %{
    org: org,
    host: host
  } do
    member = insert(:membership, organization: org, role: :owner)
    operator = conn_for(member) |> Map.put(:host, host) |> get("/")
    assert redirected_to(operator) =~ "/admin"
    refute get_session(operator, :viewer_token)
    preview = conn_for(member) |> Map.put(:host, host) |> get("/?preview=member")
    assert html_response(preview, 200)
    assert get_session(preview, :member_preview_org_id) == org.id
    refute get_session(preview, :viewer_token)
    viewer = insert(:subscribed_viewer, organization: org)

    impersonating =
      conn_for_impersonating_viewer(member, viewer) |> Map.put(:host, host) |> get("/")

    assert html_response(impersonating, 200)
    assert get_session(impersonating, :impersonating_viewer_id) == viewer.id
    assert demo_count(org) == 0
  end

  test "enabled authoritative host wins over conflicting query and ordinary tenant stays anonymous",
       %{org: org, host: host} do
    other = insert(:organization)
    conn = host_conn(host) |> get("/?org=#{other.slug}")
    assert html_response(conn, 200) =~ ~s(data-test="subscriber-demo-landing")
    refute get_session(conn, :viewer_token)
    started = conn |> recycle() |> post("/demo/subscriber?org=#{other.slug}")
    assert session_viewer(started).organization_id == org.id
    ordinary = host_conn("localhost") |> get("/?org=#{other.slug}")
    assert html_response(ordinary, 200)
    refute get_session(ordinary, :viewer_token)
    assert demo_count(other) == 0
  end

  test "HEAD and prefetch requests do not allocate identities", %{org: org, host: host} do
    conn = host_conn(host) |> head("/")
    refute get_session(conn, :viewer_token)

    for header <- ["purpose", "sec-purpose"] do
      conn = host_conn(host) |> put_req_header(header, "prefetch") |> get("/")
      refute get_session(conn, :viewer_token)
    end

    assert demo_count(org) == 0
    assert Repo.aggregate(ViewerToken, :count) == 0
  end

  test "missing playable catalog fails with retryable no-store response instead of empty demo", %{
    org: org,
    host: host
  } do
    Repo.update_all(from(v in Marquee.Content.Video, where: v.organization_id == ^org.id),
      set: [published: false]
    )

    landing = host_conn(host) |> get("/")
    assert html_response(landing, 200) =~ "Begin demo"
    conn = recycle(landing) |> post("/demo/subscriber")
    assert response(conn, 503) =~ "being prepared"
    assert_no_store(conn)
    refute get_session(conn, :viewer_token)
    assert demo_count(org) == 0
  end

  test "POST retains auth limits while landing and valid-session GET do not allocate",
       %{org: org, host: host} do
    Application.put_env(:marquee, :rate_limit_disabled, false)
    {:ok, existing} = SubscriberDemo.start_session(org)

    for {bucket, limit, key} <- [{:auth, 10, :ip}] do
      RateLimit.reset()

      for _ <- 1..limit do
        host_conn(host)
        |> assign(:organization, org)
        |> RateLimit.call(bucket: bucket, limit: limit, key: key)
      end

      landing = host_conn(host) |> get("/")
      assert html_response(landing, 200) =~ "Begin demo"
      limited = host_conn(host) |> post("/demo/subscriber")
      assert response(limited, 429)
      assert get_resp_header(limited, "retry-after") != []
      assert demo_count(org) == 1
      reused = host_conn(host) |> init_test_session(%{viewer_token: existing.token}) |> get("/")
      assert html_response(reused, 200)
      reused = recycle(reused) |> post("/demo/subscriber")
      assert response(reused, 429)
      assert session_viewer(reused).id == existing.viewer.id
      assert demo_count(org) == 1
    end
  end

  test "Begin demo requires CSRF", %{host: host, org: org} do
    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      host_conn(host)
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/demo/subscriber")
    end

    assert demo_count(org) == 0
  end

  defp session_viewer(conn) do
    token = get_session(conn, :viewer_token)
    assert is_binary(token)
    viewer = Viewers.get_viewer_by_session_token(token)
    assert viewer != nil
    viewer
  end

  defp demo_count(org),
    do:
      Repo.aggregate(
        from(v in Viewer,
          where:
            v.organization_id == ^org.id and
              fragment("?->>'subscriber_demo' = 'true'", v.metadata)
        ),
        :count
      )

  defp host_conn(host), do: build_conn() |> Map.put(:host, host)

  defp assert_no_store(conn) do
    cache_control = Enum.join(get_resp_header(conn, "cache-control"), ",")
    assert cache_control =~ "private"
    assert cache_control =~ "no-store"
  end
end
