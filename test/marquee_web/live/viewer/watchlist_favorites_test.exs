defmodule MarqueeWeb.Viewer.WatchlistFavoritesTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Engagement

  setup do
    org = insert(:organization)
    viewer = insert(:subscribed_viewer, organization: org)

    %{org: org, viewer: viewer}
  end

  describe "favorites tab" do
    test "shows favorited videos when tab is clicked", %{org: org, viewer: viewer} do
      video = insert(:video, organization: org, title: "Fav Video", mux_status: "ready")
      {:ok, _id, :added} = Engagement.toggle_favorite(org, viewer, video)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watchlist")
      view |> element(~s([data-test="favorites-tab"])) |> render_click()

      html = render(view)
      assert html =~ "Fav Video"
    end

    test "unfavorite removes from favorites tab", %{org: org, viewer: viewer} do
      video = insert(:video, organization: org, title: "To Unfav", mux_status: "ready")
      {:ok, _id, :added} = Engagement.toggle_favorite(org, viewer, video)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watchlist")
      view |> element(~s([data-test="favorites-tab"])) |> render_click()
      view |> element(~s([data-test="sv-favorite-remove-#{video.id}"])) |> render_click()

      html = render(view)
      assert html =~ "No favorites yet"
    end

    test "favorites empty state", %{viewer: viewer} do
      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watchlist")
      view |> element(~s([data-test="favorites-tab"])) |> render_click()

      html = render(view)
      assert html =~ "No favorites yet"
    end
  end

  describe "tab switching" do
    test "watchlist tab is active by default", %{viewer: viewer} do
      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watchlist")
      assert html =~ ~s(data-test="watchlist-tab")
      assert html =~ ~s(data-test="favorites-tab")
    end
  end
end
