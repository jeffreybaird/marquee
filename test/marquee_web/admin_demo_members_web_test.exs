defmodule MarqueeWeb.AdminDemoMembersWebTest do
  use MarqueeWeb.ConnCase, async: false
  import Ecto.Query
  import Phoenix.LiveViewTest
  alias Marquee.{AdminDemo, AdminDemoFixtures, Content, Repo, Viewers}

  alias Marquee.Engagement.WatchlistItem
  alias Marquee.Podcasts.Show
  alias Marquee.Viewers.{Viewer, ViewerToken}

  @moduletag :tmp_dir
  @host "demo.example.test"
  setup %{tmp_dir: dir} do
    path = Path.join(dir, "catalog.json")
    File.write!(path, Jason.encode!(AdminDemoFixtures.catalog_manifest()))
    original = Application.fetch_env(:marquee, :admin_demo)
    Application.put_env(:marquee, :admin_demo, enabled: true, host: @host, catalog_path: path)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:marquee, :admin_demo, value)
        :error -> Application.delete_env(:marquee, :admin_demo)
      end
    end)

    {:ok, _} = AdminDemo.configure_host(@host)
    {:ok, demo} = AdminDemo.start_session()

    conn =
      build_conn() |> Map.put(:host, @host) |> init_test_session(%{admin_demo_token: demo.token})

    %{demo: demo, conn: conn}
  end

  test "Members shows real private samples supports search and local access actions", %{
    conn: conn,
    demo: demo
  } do
    samples = Viewers.list_viewers(demo.organization).results
    assert length(samples) == 6
    active = Enum.find(samples, &(&1.status == :active))
    {:ok, view, html} = live(conn, "/admin/members")
    for viewer <- samples, do: assert(html =~ viewer.display_name)
    assert html =~ "Sample"
    render_change(view, "search", %{"search" => active.email})
    assert has_element?(view, "[data-test=viewer-row-#{active.id}]")
    view |> element("[data-test=suspend-viewer-#{active.id}]") |> render_click()
    assert Repo.get!(Viewer, active.id).status == :suspended
    view |> element("[data-test=reactivate-viewer-#{active.id}]") |> render_click()
    assert Repo.get!(Viewer, active.id).status == :active
  end

  test "View as resolves selected persisted identity and activity while preserving unrelated cookies",
       %{conn: conn, demo: demo} do
    selected = active_sample_with_activity(demo)
    item = Repo.one!(from w in WatchlistItem, where: w.viewer_id == ^selected.id, limit: 1)
    real_user = insert(:user)

    conn =
      conn
      |> log_in_user(real_user)
      |> put_session(:admin_demo_token, demo.token)
      |> put_session(:viewer_token, "ordinary-viewer-cookie")
      |> put_session(:impersonating_viewer_id, "ordinary-selection")

    user_token = get_session(conn, :user_token)

    conn =
      post(conn, "/viewer-session/impersonate", %{
        viewer_id: selected.id,
        return_path: "https://foreign.example/escape"
      })

    assert redirected_to(conn) == "/"
    assert get_session(conn, :admin_demo_viewer_id) == selected.id
    assert get_session(conn, :viewer_token) == "ordinary-viewer-cookie"
    assert get_session(conn, :user_token) == user_token
    assert get_session(conn, :impersonating_viewer_id) == "ordinary-selection"
    {:ok, view, html} = live(recycle(conn), "/watchlist")
    assert html =~ selected.display_name
    assert has_element?(view, "[data-test=sv-watchlist-item-#{item.id}]")

    other_items =
      Repo.all(
        from w in WatchlistItem,
          where: w.organization_id == ^demo.organization.id and w.viewer_id != ^selected.id,
          select: w.id
      )

    for id <- other_items, do: refute(has_element?(view, "[data-test=sv-watchlist-item-#{id}]"))
    assert html =~ "read-only"
    refute html =~ "Member preview — read-only."
    assert has_element?(view, "[data-test=sv-watchlist-remove-#{item.video_id}][disabled]")
    refute has_element?(view, "[data-test^=sv-card-favorite-]:not([disabled])")
    refute has_element?(view, "[data-test^=sv-card-watchlist-]:not([disabled])")
    render_click(view, "remove_watchlist_item", %{"item-id" => item.id})
    assert Repo.get!(WatchlistItem, item.id).deleted_at == nil
    {:ok, account, account_html} = live(recycle(conn), "/account")
    assert has_element?(account, "[data-test=impersonation-banner]", selected.display_name)
    assert has_element?(account, "[data-test=stop-impersonation-btn]")
    assert account_html =~ selected.subscription_status
    assert has_element?(account, "[data-test=admin-demo-feature-action][disabled]")

    stopped = conn |> recycle() |> delete("/viewer-session/impersonate")
    assert redirected_to(stopped) == "/admin/members"
    assert get_session(stopped, :admin_demo_viewer_id) == nil
    assert get_session(stopped, :viewer_token) == "ordinary-viewer-cookie"
    assert get_session(stopped, :user_token) == user_token
    assert Repo.aggregate(ViewerToken, :count) == 0
  end

  test "foreign real and other-sandbox selections are denied before session mutation", %{
    conn: conn,
    demo: demo
  } do
    real = insert(:viewer)
    {:ok, other} = AdminDemo.start_session()
    other_viewer = hd(Viewers.list_viewers(other.organization).results)
    selected = active_sample_with_activity(demo)

    for target <- [real.id, other_viewer.id, Ecto.UUID.generate()] do
      attempt =
        conn
        |> put_session(:admin_demo_viewer_id, selected.id)
        |> post("/viewer-session/impersonate", %{viewer_id: target, return_path: "/admin/members"})

      assert response(attempt, 403)
      assert get_session(attempt, :admin_demo_viewer_id) == selected.id
    end
  end

  test "View as POST and stop DELETE require CSRF tokens", %{conn: conn, demo: demo} do
    selected = active_sample_with_activity(demo)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      conn
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/viewer-session/impersonate", %{
        viewer_id: selected.id,
        return_path: "/admin/members"
      })
    end

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      conn
      |> put_private(:plug_skip_csrf_protection, false)
      |> delete("/viewer-session/impersonate")
    end
  end

  test "selected viewer uses real access state instead of an all-access preview identity", %{
    conn: conn,
    demo: demo
  } do
    selected =
      Enum.find(
        Viewers.list_viewers(demo.organization).results,
        &(&1.status == :active and &1.subscription_status == "none")
      )

    assert selected

    conn =
      post(conn, "/viewer-session/impersonate", %{
        viewer_id: selected.id,
        return_path: "/admin/members"
      })

    assert get_session(conn, :admin_demo_viewer_id) == selected.id
    video = hd(Content.list_videos(demo.organization).results)
    assert {:error, {_kind, %{to: target}}} = live(recycle(conn), "/watch/#{video.id}")
    assert target == "/subscribe"
  end

  test "reset expiry and disabled feature invalidate selected-viewer capabilities", %{
    conn: conn,
    demo: demo
  } do
    selected = active_sample_with_activity(demo)

    conn =
      post(conn, "/viewer-session/impersonate", %{
        viewer_id: selected.id,
        return_path: "/admin/members"
      })

    {:ok, selected_view, _html} = live(recycle(conn), "/watchlist")
    config = Application.fetch_env!(:marquee, :admin_demo)
    Application.put_env(:marquee, :admin_demo, Keyword.put(config, :enabled, false))
    render_click(selected_view, "switch_tab", %{"tab" => "watchlist"})
    assert_redirect(selected_view, "/demo/admin")
    Application.put_env(:marquee, :admin_demo, config)

    {:ok, replacement} = AdminDemo.reset_session(demo.token)
    assert conn |> recycle() |> get("/watchlist") |> redirected_to() == "/demo/admin"

    fresh =
      build_conn()
      |> Map.put(:host, @host)
      |> init_test_session(%{
        admin_demo_token: replacement.token,
        admin_demo_viewer_id: selected.id
      })

    rejected = get(fresh, "/watchlist")
    refute rejected.resp_body =~ selected.display_name
    config = Application.fetch_env!(:marquee, :admin_demo)
    Application.put_env(:marquee, :admin_demo, Keyword.put(config, :enabled, false))
    assert fresh |> get("/admin/members") |> redirected_to() == "/demo/admin"
    Application.put_env(:marquee, :admin_demo, config)

    Repo.update!(
      Ecto.Changeset.change(replacement.session, expires_at: DateTime.add(DateTime.utc_now(), -1))
    )

    assert fresh |> get("/admin/members") |> redirected_to() == "/demo/admin"
  end

  test "Podcasts offers existing local metadata publication and removal controls", %{
    conn: conn,
    demo: demo
  } do
    shows = Repo.all(from s in Show, where: s.organization_id == ^demo.organization.id)
    assert length(shows) == 2
    {:ok, view, html} = live(conn, "/admin/podcasts")
    for show <- shows, do: assert(html =~ show.title)
    view |> element("[data-test=new-show-btn]") |> render_click()

    view
    |> form("[data-test=show-form]",
      show: %{
        title: "Local travel audio",
        slug: "local-travel-audio",
        source_type: "direct_upload",
        access_mode: "any_active"
      }
    )
    |> render_submit()

    created =
      Repo.get_by!(Show, organization_id: demo.organization.id, slug: "local-travel-audio")

    view |> element("[data-test=toggle-published-#{created.id}]") |> render_click()
    assert Repo.get!(Show, created.id).published
    render_click(view, "sync_now", %{"id" => created.id})
    assert Repo.get!(Show, created.id).remote_last_synced_at == nil
    view |> element("[data-test=delete-show-#{created.id}]") |> render_click()
    assert Repo.get!(Show, created.id).deleted_at != nil
  end

  test "restricted features retain recognizable read-only sample screens with disabled external actions",
       %{conn: conn} do
    for {path, title} <- [
          {"/admin/plans", "Plans"},
          {"/admin/coupons", "Coupons"},
          {"/admin/webhooks", "Webhooks"},
          {"/admin/live-events", "Live"},
          {"/admin/settings/billing", "Billing"}
        ] do
      {:ok, view, html} = live(conn, path)
      assert html =~ title

      assert has_element?(
               view,
               "[data-test=admin-demo-feature-sample] [data-test=admin-demo-feature-row]"
             )

      assert has_element?(view, "[data-test=admin-demo-feature-action][disabled]")
      assert html =~ "Sample"
      assert html =~ "disabled"
    end
  end

  defp active_sample_with_activity(demo) do
    Repo.one!(
      from v in Viewer,
        join: w in WatchlistItem,
        on: w.viewer_id == v.id,
        where:
          v.organization_id == ^demo.organization.id and v.status == :active and
            v.subscription_status == "active",
        limit: 1,
        select: v
    )
  end
end
