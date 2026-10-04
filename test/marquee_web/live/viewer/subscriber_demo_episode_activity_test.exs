defmodule MarqueeWeb.Viewer.SubscriberDemoEpisodeActivityTest do
  use MarqueeWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Marquee.{Engagement, Viewers}

  test "episode selection refreshes watchlist and favorite buttons for the selected video" do
    org = insert(:organization, slug: "the-workshop", features: %{"subscriber_demo" => true})
    series = insert(:series, organization: org)
    season = insert(:season, organization: org, series: series, season_number: 1)

    first =
      insert(:video, organization: org, published: true, mux_status: "ready", duration: 180.0)

    second =
      insert(:video, organization: org, published: true, mux_status: "ready", duration: 180.0)

    insert(:episode, organization: org, season: season, video: first, episode_number: 1)
    insert(:episode, organization: org, season: season, video: second, episode_number: 2)
    conn = build_conn() |> Map.put(:host, "the-workshop.localhost") |> post("/demo/subscriber")
    viewer = Viewers.get_viewer_by_session_token(get_session(conn, :viewer_token))
    {:ok, watch, _} = live(recycle(conn), "/watch/#{first.id}")
    assert has_element?(watch, "[data-test=watchlist-btn][aria-pressed=false]")
    render_click(watch, "play_episode", %{"video-id" => second.id})
    watch |> element("[data-test=watchlist-btn]") |> render_click()
    watch |> element("[data-test=favorite-btn]") |> render_click()
    assert has_element?(watch, "[data-test=watchlist-btn][aria-pressed=true]")
    assert has_element?(watch, "[data-test=favorite-btn][aria-pressed=true]")

    render_click(watch, "play_episode", %{"video-id" => first.id})

    assert has_element?(
             watch,
             "[data-test=watchlist-btn][aria-pressed=false][aria-label='Add to watchlist']"
           )

    assert has_element?(watch, "[data-test=favorite-btn][aria-pressed=false]")
    refute Engagement.in_watchlist?(org, viewer, first)
    assert Engagement.in_watchlist?(org, viewer, second)

    render_click(watch, "play_episode", %{"video-id" => second.id})

    assert has_element?(
             watch,
             "[data-test=watchlist-btn][aria-pressed=true][aria-label='Remove from watchlist']"
           )

    assert has_element?(watch, "[data-test=favorite-btn][aria-pressed=true]")
    watch |> element("[data-test=watchlist-btn]") |> render_click()
    refute Engagement.in_watchlist?(org, viewer, second)
  end
end
