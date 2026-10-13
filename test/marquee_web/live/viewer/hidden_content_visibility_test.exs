defmodule MarqueeWeb.Viewer.HiddenContentVisibilityTest do
  @moduledoc """
  Viewers must not reach collections, series or seasons an operator has
  hidden (visible: false). Regression coverage for D1 and D2.
  """
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp insert_season_with_episode(org, series, attrs) do
    season =
      insert(:season,
        organization: org,
        series: series,
        title: attrs.title,
        season_number: attrs.number,
        visible: attrs.visible,
        episode_count: 1
      )

    video =
      insert(:video,
        organization: org,
        title: "#{attrs.title} Episode",
        mux_status: "ready",
        mux_playback_id: "pb_#{attrs.number}_#{System.unique_integer([:positive])}",
        visibility: "subscribers_only",
        duration: 600.0
      )

    episode = insert(:episode, organization: org, season: season, video: video, episode_number: 1)

    {season, episode}
  end

  # A series whose first season is hidden and second season is visible.
  defp series_with_hidden_first_season(org) do
    series = insert(:series, organization: org, title: "Night Shift", slug: "night-shift")

    {hidden, hidden_ep} =
      insert_season_with_episode(org, series, %{title: "Hidden Pilot", number: 1, visible: false})

    {shown, shown_ep} =
      insert_season_with_episode(org, series, %{title: "Visible Finale", number: 2, visible: true})

    %{series: series, hidden: hidden, hidden_ep: hidden_ep, shown: shown, shown_ep: shown_ep}
  end

  describe "hidden collection (D1)" do
    test "visible collection renders by slug" do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      insert(:collection,
        organization: org,
        slug: "open-shelf",
        title: "Open Shelf",
        visible: true
      )

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/collections/open-shelf")

      assert has_element?(view, "[data-test=sv-collection-title]", "Open Shelf")
    end

    test "hidden collection is not rendered and redirects home" do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      insert(:collection,
        organization: org,
        slug: "secret-shelf",
        title: "Secret Shelf",
        visible: false
      )

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/collections/secret-shelf")
    end
  end

  describe "hidden series (D2)" do
    test "hidden series is not rendered and redirects home" do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      series = insert(:series, organization: org, slug: "under-wraps", visible: false)

      {_season, _ep} =
        insert_season_with_episode(org, series, %{title: "S1", number: 1, visible: true})

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/series/under-wraps")
    end
  end

  describe "hidden season (D2)" do
    test "series page opens on the visible season and omits the hidden one" do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      %{series: series} = series_with_hidden_first_season(org)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/series/#{series.slug}")

      assert has_element?(view, "[data-test=season-section-heading]", "Visible Finale")
      refute has_element?(view, "[data-test=season-section-heading]", "Hidden Pilot")
      assert has_element?(view, "[data-test=season-selector] option", "Visible Finale")
      refute has_element?(view, "[data-test=season-selector] option", "Hidden Pilot")
    end

    test "requesting the hidden season number falls back to the visible season" do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      %{series: series, hidden: hidden} = series_with_hidden_first_season(org)

      {:ok, view, _html} =
        live(conn_for_viewer(viewer), ~p"/series/#{series.slug}/season/#{hidden.season_number}")

      assert has_element?(view, "[data-test=season-section-heading]", "Visible Finale")
      refute has_element?(view, "[data-test=season-section-heading]", "Hidden Pilot")
    end

    test "episode watch page season selector omits the hidden season" do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      %{shown_ep: shown_ep} = series_with_hidden_first_season(org)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{shown_ep.video_id}")

      assert has_element?(view, "[data-test=season-selector] option", "Visible Finale")
      refute has_element?(view, "[data-test=season-selector] option", "Hidden Pilot")
    end
  end
end
