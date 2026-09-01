defmodule MarqueeWeb.Viewer.WatchLiveAccessTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    org = insert(:organization)

    video =
      insert(:video,
        organization: org,
        title: "Gated Video",
        mux_status: "ready",
        mux_playback_id: "pb_gated",
        visibility: "subscribers_only",
        duration: 120.0
      )

    %{org: org, video: video}
  end

  describe "unauthenticated access" do
    test "redirects to /login", %{org: org, video: video} do
      conn =
        build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")
        |> init_test_session(%{})

      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/watch/#{video.id}")
      assert path == ~p"/login"
    end
  end

  describe "subscription gating" do
    test "unsubscribed viewer is redirected to /subscribe", %{org: org, video: video} do
      viewer = insert(:viewer, organization: org, subscription_status: "none")
      {:error, {:redirect, %{to: path}}} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      assert path == "/subscribe"
    end

    test "canceled viewer is redirected to /subscribe", %{org: org, video: video} do
      viewer = insert(:viewer, organization: org, subscription_status: "canceled")
      {:error, {:redirect, %{to: path}}} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      assert path == "/subscribe"
    end

    test "subscribed viewer can access the video", %{org: org, video: video} do
      viewer = insert(:subscribed_viewer, organization: org)
      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      assert html =~ "Gated Video"
    end
  end

  describe "video not found" do
    test "redirects to home for nonexistent video", %{org: org} do
      viewer = insert(:subscribed_viewer, organization: org)
      fake_id = Ecto.UUID.generate()

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/watch/#{fake_id}")
    end
  end

  describe "video not ready" do
    test "redirects to home for non-ready video", %{org: org} do
      viewer = insert(:subscribed_viewer, organization: org)

      video =
        insert(:video,
          organization: org,
          mux_status: "preparing",
          mux_playback_id: "pb_prep"
        )

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
    end
  end

  describe "multi-tenant isolation" do
    test "viewer cannot watch video from another org", %{video: video} do
      other_org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: other_org)

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
    end
  end
end
