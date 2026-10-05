defmodule MarqueeWeb.AdminDemoWebTest do
  use MarqueeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Marquee.{AdminDemo, Repo, TenantDomains}

  alias Marquee.Accounts.Organization
  alias MarqueeWeb.Plugs.RateLimit

  @moduletag :tmp_dir
  @host "demo-marquee.example.test"

  setup %{tmp_dir: dir} do
    path = Path.join(dir, "travel.json")
    File.write!(path, Jason.encode!(Marquee.AdminDemoFixtures.catalog_manifest()))

    changes = [
      admin_demo: [enabled: true, host: @host, catalog_path: path],
      rate_limit_disabled: true
    ]

    originals = Map.new(changes, fn {key, _} -> {key, Application.fetch_env(:marquee, key)} end)
    for {key, value} <- changes, do: Application.put_env(:marquee, key, value)

    on_exit(fn ->
      for {key, value} <- originals do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end

      RateLimit.reset()
    end)

    {:ok, _} = AdminDemo.configure_host(@host)
    :ok
  end

  test "entry GET issues a signed-session nonce without allocating and POST refresh reuses private auth" do
    entry = host_conn() |> get("/demo/admin")
    assert html_response(entry, 200) =~ ~s(data-test="admin-demo-entry-form")
    assert_private(entry)
    assert is_binary(get_session(entry, :admin_demo_entry_key))
    assert sandbox_count() == 0
    conn = entry |> recycle() |> post("/demo/admin")
    assert redirected_to(conn) == "/admin"
    token = get_session(conn, :admin_demo_token)
    assert {:ok, %{scope: scope}} = AdminDemo.get_session(token)
    assert scope.organization.demo_kind == :admin_sandbox
    assert sandbox_count() == 1
    assert_private(conn |> recycle() |> get("/admin"))
    {:ok, view, html} = live(recycle(conn), "/admin")
    assert html =~ ~s(data-test="admin-demo-bar")
    assert render(view) =~ ~s(data-test="admin-demo-bar")
    repeated = conn |> recycle() |> post("/demo/admin")
    assert get_session(repeated, :admin_demo_token) == token
    assert sandbox_count() == 1
  end

  test "dedicated demo capability preserves real operator and viewer auth keys" do
    user = insert(:user)
    conn = host_conn() |> log_in_user(user) |> put_session(:viewer_token, "existing-viewer-token")
    normal_token = get_session(conn, :user_token)
    entered = conn |> get("/demo/admin") |> recycle() |> post("/demo/admin")
    assert get_session(entered, :user_token) == normal_token
    assert get_session(entered, :viewer_token) == "existing-viewer-token"
    assert get_session(entered, :admin_demo_token) != normal_token
    exited = entered |> recycle() |> post("/demo/admin/exit")
    assert get_session(exited, :user_token) == normal_token
    assert get_session(exited, :viewer_token) == "existing-viewer-token"
    assert get_session(exited, :admin_demo_token) == nil
    assert redirected_to(exited) == MarqueeWeb.Endpoint.url() <> "/"
  end

  test "foreign hosts cannot start or authenticate a private demo" do
    conn = entered_conn()
    token = get_session(conn, :admin_demo_token)

    foreign =
      build_conn()
      |> Map.put(:host, "foreign.example.test")
      |> init_test_session(%{admin_demo_token: token})

    assert foreign |> post("/demo/admin") |> response(404)
    assert sandbox_count() == 1
    response = foreign |> get("/admin")
    refute response.resp_body =~ ~s(data-test="admin-demo-bar")
  end

  test "guessed sandbox slugs cannot expose the private catalog through public query resolution" do
    conn = entered_conn()
    {:ok, %{scope: scope}} = AdminDemo.get_session(get_session(conn, :admin_demo_token))
    public = build_conn() |> get("/?org=#{scope.organization.slug}")
    refute public.resp_body =~ "Travel fixture 1"
    refute public.resp_body =~ ~s(data-test="admin-demo-bar")
    assert public.status in [302, 404]
  end

  test "two browsers receive isolated scopes and private previews" do
    first = entered_conn()
    second = entered_conn()
    {:ok, %{scope: a}} = AdminDemo.get_session(get_session(first, :admin_demo_token))
    {:ok, %{scope: b}} = AdminDemo.get_session(get_session(second, :admin_demo_token))
    refute a.organization.id == b.organization.id
    assert_private(first |> recycle() |> get("/?preview=member"))
    {:ok, _view, html} = live(recycle(first), "/?preview=member")
    assert html =~ "Travel fixture 1"
    assert html =~ ~s(data-test="admin-demo-bar")
  end

  test "reset creates a fresh sandbox once and exit revokes its capability" do
    conn = entered_conn()
    old_token = get_session(conn, :admin_demo_token)
    reset = conn |> recycle() |> post("/demo/admin/reset")
    assert redirected_to(reset) == "/admin"
    new_token = get_session(reset, :admin_demo_token)
    refute old_token == new_token
    assert {:error, :revoked} = AdminDemo.get_session(old_token)
    repeated = conn |> recycle() |> post("/demo/admin/reset")
    assert get_session(repeated, :admin_demo_token) == new_token
    exit_conn = reset |> recycle() |> post("/demo/admin/exit")
    assert {:error, :revoked} = AdminDemo.get_session(new_token)
    assert get_session(exit_conn, :admin_demo_token) == nil
  end

  test "persisted expiry and kill switch deny subsequent requests and live events" do
    conn = entered_conn()
    {:ok, view, _} = live(recycle(conn), "/admin/content")
    config = Application.fetch_env!(:marquee, :admin_demo)
    Application.put_env(:marquee, :admin_demo, Keyword.put(config, :enabled, false))
    render_click(view, "search", %{"search" => "Travel"})
    assert_redirect(view, "/demo/admin")
    denied = conn |> recycle() |> get("/admin")
    assert redirected_to(denied) == "/demo/admin"
    Application.put_env(:marquee, :admin_demo, config)
    {:ok, %{session: session}} = AdminDemo.get_session(get_session(conn, :admin_demo_token))

    session
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    assert conn |> recycle() |> get("/admin") |> redirected_to() == "/demo/admin"
  end

  test "unsupported billing routes explain restrictions while approved sample library works" do
    conn = entered_conn()
    {:ok, _view, html} = live(recycle(conn), "/admin/settings/billing")
    assert html =~ ~s(data-test="admin-demo-restricted")
    {:ok, view, _} = live(recycle(conn), "/admin/demo/library")
    view |> element("[data-test=sample-clip-travel-fixture-4]") |> render_click()
    {:ok, %{scope: scope}} = AdminDemo.get_session(get_session(conn, :admin_demo_token))

    assert Repo.exists?(
             from v in Marquee.Content.Video,
               where:
                 v.organization_id == ^scope.organization.id and
                   v.mux_playback_id == "fixture-travel-playback-4"
           )
  end

  test "entry rate limit rejects the fourth allocation attempt from one IP" do
    Application.put_env(:marquee, :rate_limit_disabled, false)
    RateLimit.reset()

    for _ <- 1..3 do
      assert entered_conn() |> redirected_to() == "/admin"
    end

    limited = host_conn() |> get("/demo/admin") |> recycle() |> post("/demo/admin")
    assert response(limited, 429)
    assert sandbox_count() == 3

    RateLimit.reset()
    active = entered_conn()
    RateLimit.reset()

    final =
      Enum.reduce(1..3, active, fn _, conn ->
        reset = conn |> recycle() |> post("/demo/admin/reset")
        assert redirected_to(reset) == "/admin"
        reset
      end)

    count = sandbox_count()
    denied = final |> recycle() |> post("/demo/admin/reset")
    assert response(denied, 429)
    assert sandbox_count() == count
  end

  test "state-changing entry reset and exit reject missing CSRF tokens" do
    entry = host_conn() |> get("/demo/admin")

    for path <- ["/demo/admin", "/demo/admin/reset", "/demo/admin/exit"] do
      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        entry |> recycle() |> put_private(:plug_skip_csrf_protection, false) |> post(path)
      end
    end

    assert sandbox_count() == 0
  end

  test "trusted exact proxy keeps independent client IP rate buckets" do
    proxy = {172, 18, 0, 2}
    enable_proxy_limit(proxy)

    for client <- ["192.0.2.10", "192.0.2.11"] do
      for _ <- 1..3, do: assert(proxy_entry(proxy, client).status == 302)
      assert proxy_entry(proxy, client).status == 429
    end

    assert sandbox_count() == 6
  end

  test "untrusted peers cannot bypass entry limit by spoofing forwarded IPs" do
    enable_proxy_limit({172, 18, 0, 2})
    peer = {192, 0, 2, 99}
    for n <- 1..3, do: assert(proxy_entry(peer, "198.51.100.#{n}").status == 302)
    assert proxy_entry(peer, "198.51.100.4").status == 429
    assert sandbox_count() == 3
  end

  test "malformed or multivalued forwarded IPs fail closed to the trusted peer bucket" do
    proxy = {172, 18, 0, 2}
    enable_proxy_limit(proxy)

    for header <- ["not-an-ip", "192.0.2.1, 192.0.2.2", "192.0.2.3:8080"] do
      assert proxy_entry(proxy, header).status == 302
    end

    assert proxy_entry(proxy, "192.0.2.4, 192.0.2.5").status == 429
    assert sandbox_count() == 3
  end

  defp enable_proxy_limit(proxy) do
    Application.put_env(:marquee, :rate_limit_disabled, false)
    config = Application.fetch_env!(:marquee, :admin_demo)
    Application.put_env(:marquee, :admin_demo, Keyword.put(config, :trusted_proxy_ip, proxy))
    RateLimit.reset()
  end

  defp proxy_entry(peer, client) do
    host_conn()
    |> Map.put(:remote_ip, peer)
    |> put_req_header("x-forwarded-for", client)
    |> get("/demo/admin")
    |> recycle()
    |> Map.put(:remote_ip, peer)
    |> put_req_header("x-forwarded-for", client)
    |> post("/demo/admin")
  end

  test "Stripe return callback is denied before its direct provider call" do
    conn = entered_conn() |> recycle() |> get("/admin/settings/stripe/return")
    assert redirected_to(conn) == "/admin/demo/restricted"
  end

  test "private demo visitors can browse their catalog without operational route restrictions" do
    conn = entered_conn()
    {:ok, _view, html} = live(recycle(conn), "/browse")
    assert html =~ ~s(data-test="admin-demo-bar")
    assert html =~ ~s(data-test="impersonation-banner")
    assert html =~ "Travel fixture 1"
    refute html =~ ~s(data-test="admin-demo-restricted")
  end

  test "content page tour is opt-in for demo visitors including after reset" do
    conn = entered_conn()

    Enum.reduce(1..2, conn, fn attempt, visit ->
      {:ok, view, _} = live(recycle(visit), "/admin/content")
      assert has_element?(view, "[phx-hook=PageTour][data-auto-start=false]")
      assert has_element?(view, "[data-test=restart-page-tour]")
      view |> element("[data-test=restart-page-tour]") |> render_click()
      assert_push_event(view, "start-page-tour", %{})
      if attempt == 1, do: visit |> recycle() |> post("/demo/admin/reset"), else: visit
    end)
  end

  test "dashboard presents labeled sample analytics an anonymous identity and optional tour" do
    conn = entered_conn()
    {:ok, %{scope: scope}} = AdminDemo.get_session(get_session(conn, :admin_demo_token))
    {:ok, view, html} = live(recycle(conn), "/admin")
    assert html =~ "Demo admin"
    refute html =~ scope.user.email
    assert html =~ "Sample analytics"
    refute html =~ "No viewers yet."
    refute html =~ "Connect Stripe"
    refute html =~ "Create a plan"
    assert has_element?(view, "#admin-guided-tour[data-auto-start=false]")
    assert has_element?(view, "[data-test=restart-tour]")

    value =
      view
      |> element("[data-test=kpi-total-views]")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.text()
      |> String.replace("Total Views (30d)", "")

    assert value |> String.replace(",", "") |> String.trim() |> String.to_integer() > 0
    assert has_element?(view, "[data-test=admin-demo-edit-tasks]")
  end

  test "platform marketing links the private admin demo only when enabled and hostname ready" do
    pattern = "{slug}-marquee.example.test"

    changes = [
      tenant_host_pattern: pattern,
      tenant_domain_provisioning: [
        enabled: true,
        zone: "example.test",
        account_id: "123",
        api_token: "fixture",
        target_ipv4: "192.0.2.25",
        host_pattern: pattern
      ]
    ]

    originals = Map.new(changes, fn {key, _} -> {key, Application.fetch_env(:marquee, key)} end)
    for {key, value} <- changes, do: Application.put_env(:marquee, key, value)

    on_exit(fn ->
      for {key, value} <- originals do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end
    end)

    {:ok, host} = AdminDemo.configure_host(@host)

    {:ok, domain} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        TenantDomains.request_demo_host_provisioning(host)
      end)

    refute build_conn() |> get("/") |> html_response(200) =~ ~s(data-test="admin-demo-cta")

    Repo.update!(
      Ecto.Changeset.change(domain,
        status: :ready,
        dns_record_id: "fixture",
        ready_at: DateTime.utc_now()
      )
    )

    html = build_conn() |> get("/") |> html_response(200)

    assert Floki.find(
             Floki.parse_document!(html),
             ~s([data-test=admin-demo-cta][href="https://#{@host}/demo/admin"])
           ) != []

    config = Application.fetch_env!(:marquee, :admin_demo)
    Application.put_env(:marquee, :admin_demo, Keyword.put(config, :enabled, false))
    refute build_conn() |> get("/") |> html_response(200) =~ ~s(data-test="admin-demo-cta")
  end

  test "connected unsupported navigation is restricted before operational views mount" do
    conn = entered_conn()

    for path <- ["/admin/plans", "/admin/podcasts"] do
      {:ok, view, _} = live(recycle(conn), "/admin")

      assert {:error, {:redirect, %{status: 302, to: "/admin/demo/restricted"}}} =
               live_redirect(view, to: path)
    end
  end

  defp entered_conn do
    host_conn() |> get("/demo/admin") |> recycle() |> post("/demo/admin")
  end

  defp host_conn, do: build_conn() |> Map.put(:host, @host)

  defp assert_private(conn) do
    value = conn |> get_resp_header("cache-control") |> Enum.join(",")
    assert value =~ "private"
    assert value =~ "no-store"
  end

  defp sandbox_count,
    do: Repo.aggregate(from(o in Organization, where: o.demo_kind == :admin_sandbox), :count)
end
