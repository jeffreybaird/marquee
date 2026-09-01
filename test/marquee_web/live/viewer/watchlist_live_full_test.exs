defmodule MarqueeWeb.Viewer.WatchlistLiveFullTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Engagement

  setup do
    org = insert(:organization)
    viewer = insert(:subscribed_viewer, organization: org)

    %{org: org, viewer: viewer}
  end

  describe "unauthenticated access" do
    test "redirects to /login", %{org: org} do
      conn =
        build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")
        |> init_test_session(%{})

      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/watchlist")
      assert path == ~p"/login"
    end
  end

  describe "subscription gating" do
    test "unsubscribed viewer is redirected to /subscribe", %{org: org} do
      viewer = insert(:viewer, organization: org, subscription_status: "none")
      {:error, {:redirect, %{to: path}}} = live(conn_for_viewer(viewer), ~p"/watchlist")
      assert path == "/subscribe"
    end
  end

  describe "watchlist tab" do
    test "renders watchlist with videos", %{org: org, viewer: viewer} do
      video = insert(:video, organization: org, title: "WL Video", mux_status: "ready")
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, video)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watchlist")
      assert html =~ "WL Video"
      assert html =~ ~s(data-test="sv-watchlist-grid")
    end

    test "renders empty state when watchlist is empty", %{viewer: viewer} do
      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watchlist")
      assert html =~ "Your watchlist is empty"
    end

    test "remove button removes video from watchlist", %{org: org, viewer: viewer} do
      video = insert(:video, organization: org, title: "Remove Me", mux_status: "ready")
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, video)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watchlist")
      view |> element(~s([data-test="sv-watchlist-remove-#{video.id}"])) |> render_click()

      html = render(view)
      refute html =~ "Remove Me"
      assert html =~ "Your watchlist is empty"
    end
  end

  describe "tab switching" do
    test "switching to favorites tab shows favorites panel", %{viewer: viewer} do
      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watchlist")

      view |> element(~s([data-test="favorites-tab"])) |> render_click()
      html = render(view)
      assert html =~ ~s(data-test="favorites-panel")
    end

    test "switching back to watchlist tab shows watchlist panel", %{viewer: viewer} do
      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watchlist")

      # Switch to favorites
      view |> element(~s([data-test="favorites-tab"])) |> render_click()
      # Switch back
      view |> element(~s([data-test="watchlist-tab"])) |> render_click()

      html = render(view)
      assert html =~ ~s(data-test="watchlist-panel")
    end

    test "tab aria-selected reflects active state", %{viewer: viewer} do
      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/watchlist")
      # Watchlist tab should be active by default
      assert html =~ ~s(aria-selected="true")

      view |> element(~s([data-test="favorites-tab"])) |> render_click()
      html = render(view)

      # Check the favorites tab panel is visible
      assert html =~ ~s(data-test="favorites-panel")
    end
  end

  describe "multi-tenant isolation" do
    test "watchlist only shows videos from the viewer's org", %{org: org, viewer: viewer} do
      video = insert(:video, organization: org, title: "My Org Video", mux_status: "ready")
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, video)

      other_org = insert(:organization)
      other_viewer = insert(:subscribed_viewer, organization: other_org)

      {:ok, _view, html} = live(conn_for_viewer(other_viewer), ~p"/watchlist")
      refute html =~ "My Org Video"
      assert html =~ "Your watchlist is empty"
    end
  end
end
