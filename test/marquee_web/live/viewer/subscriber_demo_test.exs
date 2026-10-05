defmodule MarqueeWeb.Viewer.SubscriberDemoTest do
  use MarqueeWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Marquee.{Engagement, SubscriberDemo, Viewers}

  setup do
    org = insert(:organization, slug: "the-workshop", features: %{"subscriber_demo" => true})

    insert(:row,
      organization: org,
      title: "Continue Watching",
      source_type: :continue_watching,
      visible: true
    )

    video =
      insert(:video, organization: org, published: true, mux_status: "ready", duration: 180.0)

    another =
      insert(:video, organization: org, published: true, mux_status: "ready", duration: 180.0)

    conn = build_conn() |> Map.put(:host, "#{org.slug}.localhost")
    %{org: org, video: video, another: another, demo_conn: conn}
  end

  test "platform homepage exposes the subscriber demo entry" do
    {:ok, home, _} = live(build_conn(), "/")
    assert has_element?(home, "[data-test=subscriber-demo-entry]", "Try the subscriber demo")
  end

  test "existing real viewer remains authenticated when visiting demo entry", %{org: org} do
    viewer = insert(:subscribed_viewer, organization: org)
    conn = viewer |> conn_for_viewer() |> post("/demo/subscriber")
    assert Viewers.get_viewer_by_session_token(get_session(conn, :viewer_token)).id == viewer.id

    refute SubscriberDemo.demo_viewer?(
             Viewers.get_viewer_by_session_token(get_session(conn, :viewer_token))
           )
  end

  test "demo sessions cannot enter account and payment workflows", %{demo_conn: conn} do
    conn = post(conn, "/demo/subscriber")

    for path <- ["/account", "/subscribe", "/account/payment-issue"] do
      assert {:error, {:redirect, %{to: "/"}}} = live(recycle(conn), path)
    end
  end

  test "entry starts an isolated session and reuses it on repeat visits", %{
    demo_conn: conn,
    org: org
  } do
    {:ok, home, _} = live(conn, "/")
    assert has_element?(home, "[data-test=subscriber-demo-banner]", "Demo")
    started = post(conn, "/demo/subscriber")
    assert redirected_to(started) == "/"
    token = get_session(started, :viewer_token)
    viewer = Viewers.get_viewer_by_session_token(token)
    assert viewer.organization_id == org.id
    assert SubscriberDemo.demo_viewer?(viewer)
    repeated = started |> recycle() |> post("/demo/subscriber")

    assert Viewers.get_viewer_by_session_token(get_session(repeated, :viewer_token)).id ==
             viewer.id

    second = post(conn, "/demo/subscriber")
    assert Viewers.get_viewer_by_session_token(get_session(second, :viewer_token)).id != viewer.id
    {:ok, home, _} = live(recycle(started), "/")
    assert has_element?(home, "[data-test=subscriber-demo-banner]", "Demo")
  end

  test "playback and another video's watchlist persist across navigation", %{
    demo_conn: conn,
    org: org,
    video: video,
    another: another
  } do
    conn = post(conn, "/demo/subscriber")
    viewer = Viewers.get_viewer_by_session_token(get_session(conn, :viewer_token))
    {:ok, watch, _} = live(recycle(conn), "/watch/#{video.id}")
    assert has_element?(watch, "[data-test=mux-player]")
    render_click(watch, "playback_paused", %{"video_id" => video.id, "position" => 42})
    {:ok, other, _} = live(recycle(conn), "/watch/#{another.id}")
    other |> element("[data-test=watchlist-btn]") |> render_click()
    assert Engagement.in_watchlist?(org, viewer, another)
    {:ok, list, _} = live(recycle(conn), "/watchlist")
    assert has_element?(list, "[data-test=sv-watchlist-remove-#{another.id}]")
    {:ok, home, _} = live(recycle(conn), "/")
    assert has_element?(home, "a[href='/watch/#{video.id}']")
    assert render(home) =~ "Continue Watching"

    assert Enum.any?(
             Engagement.list_continue_watching(org, viewer).results,
             &(&1.video.id == video.id)
           )

    {:ok, resumed, _} = live(recycle(conn), "/watch/#{video.id}")
    assert has_element?(resumed, "[data-resume-position='42.0']")
  end

  test "a demo token grants no access to another tenant", %{demo_conn: conn} do
    started = post(conn, "/demo/subscriber")
    other = insert(:organization)
    other_conn = started |> recycle() |> Map.put(:host, "#{other.slug}.localhost")
    assert {:error, {:redirect, %{to: "/login"}}} = live(other_conn, "/watchlist")
    denied = post(other_conn, "/demo/subscriber")
    assert denied.status == 403
  end

  test "expiry blocks writes from an already connected player", %{
    demo_conn: conn,
    org: org,
    video: video
  } do
    started = post(conn, "/demo/subscriber")
    viewer = Viewers.get_viewer_by_session_token(get_session(started, :viewer_token))
    {:ok, watch, _} = live(recycle(started), "/watch/#{video.id}")
    past = DateTime.utc_now() |> DateTime.add(-60) |> DateTime.to_iso8601()

    viewer
    |> Ecto.Changeset.change(
      metadata: Map.put(viewer.metadata, "subscriber_demo_expires_at", past)
    )
    |> Marquee.Repo.update!()

    render_click(watch, "toggle_watchlist", %{})
    refute Engagement.in_watchlist?(org, viewer, video)
    assert {:error, {:redirect, %{to: "/login"}}} = live(recycle(started), "/watch/#{video.id}")
  end
end
