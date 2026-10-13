defmodule MarqueeFeatures.Steps.ContentConsumption do
  @moduledoc """
  Step definitions for the viewer-side content consumption features:

    * content_consumption__content_discovery_and_browsing.feature
    * content_consumption__queue_management.feature
    * content_consumption__video_playback.feature
    * content_consumption__watch_history.feature
    * content_consumption__watchlist_and_favorites.feature

  Browser-driven through Wallaby. A viewer signs in through a magic link and
  drives the real viewer site (homepage rows, browse grid, watch page, queue,
  watchlist, favorites and history). Mux is mocked and no video bytes are
  served: playback is exercised by dispatching the `pause` / `ended` events
  the MuxPlayer hook listens for on the `<mux-player>` element, and the
  resulting server-side state (progress, history, queue advance) is asserted
  through the Engagement context and the player's data attributes.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Marquee.Factory
  import ExUnit.Assertions
  import MarqueeFeatures.Support.Browser

  alias Marquee.Content
  alias Marquee.Engagement
  alias Marquee.Repo
  alias Marquee.Viewers.ViewerToken

  # ---- Background ---------------------------------------------------------

  # A tenant viewer site: an organization whose operator has published a
  # public landing page with a free-to-watch content row. Anonymous visitors
  # see that landing page; signed-in members see the catalog homepage.
  given_ "I am on a tenant viewer site", fn world ->
    org = insert(:organization)
    collection = insert(:collection, organization: org, title: "Free to watch")

    videos =
      for index <- 0..1 do
        video = ready_video(org, title: "Public #{index}", visibility: "public")
        insert(:collection_item, organization: org, collection: collection, video: video, position: index)
        video
      end

    insert(:landing_section,
      organization: org,
      section_type: :content_row,
      position: 0,
      config: %{"title" => "Free to watch", "source_type" => "collection", "source_id" => collection.id}
    )

    Map.merge(world, %{org: org, public_collection: collection, public_videos: videos})
  end

  given_ "I am not logged in", fn world ->
    Map.put(world, :viewer, nil)
  end

  given_ "I am logged in as a viewer", fn world ->
    log_in_viewer(world)
  end

  given_ "I am logged in as a viewer with an active subscription", fn world ->
    log_in_viewer(world)
  end

  # ---- Content discovery and browsing -------------------------------------

  given_ "the organization has configured catalog rows and a hero banner", fn world ->
    org = world.org
    hero_row = insert(:hero_row, organization: org)

    hero_video = ready_video(org, title: "Hero feature")

    insert(:hero_slide,
      organization: org,
      row: hero_row,
      video: hero_video,
      position: 0,
      headline: "Featured tonight",
      background_image_url: "/images/logo.svg"
    )

    row = insert(:row, organization: org, title: "Operator picks", position: 1)

    videos =
      for index <- 0..2 do
        video = ready_video(org, title: "Pick #{index}")
        insert(:row_item, organization: org, row: row, video: video, position: index)
        video
      end

    Map.merge(world, %{hero_row: hero_row, row: row, videos: videos})
  end

  # The catalog homepage (hero + rows) is the signed-in member view; an
  # anonymous visitor gets the org landing page instead. "Viewer" scenarios
  # sign a member in unless the scenario said "I am not logged in".
  when_ "I navigate to the homepage", fn world ->
    world = ensure_viewer_session(world)
    Map.put(world, :session, visit_page(world.session, org_path(world, "/")))
  end

  then_ "I see the hero banner and content rows as configured by the operator", fn world ->
    session =
      world.session
      |> assert_has(css("[data-test=hero-carousel]"))
      |> assert_has(css("[data-test=hero-slide-0]", text: "Featured tonight"))
      |> assert_has(css("[data-test='content-row-#{world.row.id}']", text: "Operator picks"))

    Enum.each(world.videos, fn video ->
      assert_has(session, css("[data-test='content-row-#{world.row.id}'] [data-test='sv-card-#{video.id}']"))
    end)

    Map.put(world, :session, session)
  end

  then_ "I see publicly visible content rows", fn world ->
    session =
      world.session
      |> assert_has(css("[data-test=landing-page]"))
      |> assert_has(css("[data-test=content-row-section]", text: world.public_collection.title))

    Enum.each(world.public_videos, fn video ->
      assert_has(session, css("[data-test=content-row-section]", text: video.title))
    end)

    Map.put(world, :session, session)
  end

  then_ "I am prompted to log in or subscribe to access gated content", fn world ->
    world.session
    |> assert_gone(css("[data-test=viewer-sign-out]"))
    |> assert_has(css("[data-test=sign-in-link]", text: "Sign In"))

    world
  end

  given_ "a collection is visible on the platform", fn world ->
    org = world.org
    collection = insert(:collection, organization: org, title: "Summer Series", visible: true)

    videos =
      for index <- 0..2 do
        video = ready_video(org, title: "Summer episode #{index}", visibility: "public")
        insert(:collection_item, organization: org, collection: collection, video: video, position: index)
        video
      end

    Map.merge(world, %{collection: collection, videos: videos})
  end

  when_ "I navigate to the collection page", fn world ->
    session = visit_page(world.session, org_path(world, "/collections/#{world.collection.slug}"))
    Map.put(world, :session, session)
  end

  then_ "I see the collection's title and its videos", fn world ->
    session =
      assert_has(world.session, css("[data-test=sv-collection-title]", text: world.collection.title))

    Enum.each(world.videos, fn video ->
      assert_has(session, css("[data-test=sv-collection-grid] [data-test='sv-card-#{video.id}']"))
    end)

    Map.put(world, :session, session)
  end

  given_ "videos with various tags exist on the homepage", fn world ->
    org = world.org
    drama = insert(:tag, organization: org, name: "Drama")
    comedy = insert(:tag, organization: org, name: "Comedy")

    drama_video = ready_video(org, title: "A drama", visibility: "public")
    comedy_video = ready_video(org, title: "A comedy", visibility: "public")
    insert(:video_tag, organization: org, video: drama_video, tag: drama)
    insert(:video_tag, organization: org, video: comedy_video, tag: comedy)

    session =
      world.session
      |> visit_page(org_path(world, "/browse"))
      |> assert_has(css("[data-test='sv-card-#{drama_video.id}']"))
      |> assert_has(css("[data-test='sv-card-#{comedy_video.id}']"))

    Map.merge(world, %{
      session: session,
      tag: drama,
      tagged_video: drama_video,
      untagged_video: comedy_video
    })
  end

  when_ "I select a tag filter", fn world ->
    session = select_option(world.session, "[data-test=sv-filter-tag]", world.tag.id)
    Map.put(world, :session, session)
  end

  then_ "only videos with that tag are shown", fn world ->
    world.session
    |> assert_has(css("[data-test=sv-browse-grid] [data-test='sv-card-#{world.tagged_video.id}']"))
    |> assert_gone(css("[data-test='sv-card-#{world.untagged_video.id}']"))

    world
  end

  given_ "a catalog row exists with more items than fit in the default view", fn world ->
    org = world.org
    collection = insert(:collection, organization: org, title: "Deep catalog")

    videos =
      for index <- 0..7 do
        video = ready_video(org, title: "Deep item #{index}", visibility: "public")
        insert(:collection_item, organization: org, collection: collection, video: video, position: index)
        video
      end

    # The row only surfaces a slice of the collection; "view all" shows the rest.
    row =
      insert(:row,
        organization: org,
        title: "Deep catalog",
        source_type: :collection,
        source_id: collection.id,
        max_items: 5,
        position: 0
      )

    Map.merge(world, %{row: row, collection: collection, videos: videos})
  end

  when_ "I click to view all items in that row", fn world ->
    world = ensure_viewer_session(world)
    row_selector = "[data-test='content-row-#{world.row.id}']"

    session =
      world.session
      |> visit_page(org_path(world, "/"))
      |> assert_has(css(row_selector))

    # The row itself only surfaces `max_items` of the collection.
    assert_eventually(fn -> length(card_video_ids(session, row_selector)) == world.row.max_items end)

    session =
      session
      |> click(css("[data-test='view-all-#{world.row.id}']"))
      |> await_live_connect()

    Map.put(world, :session, session)
  end

  then_ "I see the full list of content in that row", fn world ->
    session = assert_has(world.session, css("[data-test=sv-collection-title]", text: world.row.title))

    Enum.each(world.videos, fn video ->
      assert_has(session, css("[data-test=sv-collection-grid] [data-test='sv-card-#{video.id}']"))
    end)

    Map.put(world, :session, session)
  end

  # ---- Shared setup: videos, series, collections --------------------------

  given_ "a video is available", fn world ->
    Map.put(world, :video, ready_video(world.org, title: "Available video"))
  end

  given_ "a ready video exists", fn world ->
    Map.put(world, :video, ready_video(world.org, title: "Ready video"))
  end

  given_ "a series is available", fn world ->
    series = build_series(world.org, seasons: 1, episodes: 2)
    Map.merge(world, %{series: series.series, season: series.season, episodes: series.episodes})
  end

  given_ "a series exists with at least one season and episode", fn world ->
    series = build_series(world.org, seasons: 1, episodes: 2)
    Map.merge(world, %{series: series.series, season: series.season, episodes: series.episodes})
  end

  given_ "a series has multiple seasons", fn world ->
    series = build_series(world.org, seasons: 2, episodes: 2)

    Map.merge(world, %{
      series: series.series,
      season: series.season,
      seasons: series.seasons,
      episodes: series.episodes
    })
  end

  given_ "a collection exists with videos", fn world ->
    org = world.org
    collection = insert(:collection, organization: org, title: "Queue me")

    videos =
      for index <- 0..2 do
        video = ready_video(org, title: "Queue me #{index}")
        insert(:collection_item, organization: org, collection: collection, video: video, position: index)
        video
      end

    Map.merge(world, %{collection: collection, videos: videos})
  end

  # ---- Queue management ---------------------------------------------------

  when_ "I add it to my queue", fn world ->
    session =
      world.session
      |> visit_page(org_path(world, "/browse"))
      |> click(css("[data-test='sv-card-queue-#{world.video.id}']"))
      |> assert_has(css("[data-test='sv-card-queue-#{world.video.id}'][aria-pressed='true']"))

    Map.put(world, :session, session)
  end

  then_ "it appears at the end of my queue", fn world ->
    %{results: items} = Engagement.list_queue(world.org, world.viewer, per_page: 100)
    assert List.last(items).video_id == world.video.id

    session =
      world.session
      |> visit_page(org_path(world, "/queue"))
      |> assert_has(css("[data-test=sv-queue-list] [data-test='sv-queue-item-#{world.video.id}']:last-child"))

    Map.put(world, :session, session)
  end

  given_ "I have items in my queue and am currently watching", fn world ->
    world
    |> seed_queue(2)
    |> start_watching()
  end

  when_ "I add a video as \"play next\"", fn world ->
    video = ready_video(world.org, title: "Play me next")

    session =
      world.session
      |> click(css("[data-test='play-next-#{video.id}']"))

    Map.merge(world, %{session: session, play_next_video: video})
  end

  then_ "that video is inserted at the front of the queue", fn world ->
    %{results: [first | _]} = Engagement.list_queue(world.org, world.viewer, per_page: 100)
    assert first.video_id == world.play_next_video.id

    world.session
    |> assert_has(css("[data-test=queue-list] [data-test='queue-item-#{world.play_next_video.id}']:first-child"))

    world
  end

  given_ "I have items in my queue", fn world ->
    seed_queue(world, 3)
  end

  given_ "I have multiple items in my queue", fn world ->
    seed_queue(world, 3)
  end

  when_ "I remove one item", fn world ->
    [_first, removed | _rest] = world.queue_videos

    session =
      world.session
      |> visit_page(org_path(world, "/queue"))
      |> assert_has(css("[data-test='sv-queue-item-#{removed.id}']"))
      # The remove control is revealed on hover, as for a pointer user.
      |> hover(css("[data-test='sv-queue-item-#{removed.id}']"))
      |> click(css("[data-test='sv-queue-remove-#{removed.id}']"))
      |> assert_gone(css("[data-test='sv-queue-item-#{removed.id}']"))

    Map.merge(world, %{session: session, removed_video: removed})
  end

  then_ "it is deleted from the queue", fn world ->
    %{results: items} = Engagement.list_queue(world.org, world.viewer, per_page: 100)
    refute Enum.any?(items, &(&1.video_id == world.removed_video.id))
    world
  end

  then_ "the remaining items maintain their order", fn world ->
    expected = world.queue_videos |> Enum.reject(&(&1.id == world.removed_video.id)) |> Enum.map(& &1.id)

    %{results: items} = Engagement.list_queue(world.org, world.viewer, per_page: 100)
    assert Enum.map(items, & &1.video_id) == expected
    assert Enum.map(items, & &1.position) == Enum.to_list(0..(length(expected) - 1))

    assert queue_dom_order(world.session, "sv-queue-item-") == expected
    world
  end

  when_ "I drag an item to a new position", fn world ->
    [first, _second, last] = world.queue_videos

    session =
      world.session
      |> visit_page(org_path(world, "/queue"))
      |> assert_has(css("[data-test='sv-queue-item-#{last.id}']"))
      |> execute_script(drag_script("[data-test=sv-queue-list]", last.id, first.id))

    Map.merge(world, %{session: session, dragged_video: last})
  end

  then_ "the queue updates to reflect the new order", fn world ->
    [first, second, last] = world.queue_videos
    expected = [last.id, first.id, second.id]

    session =
      assert_has(
        world.session,
        css("[data-test=sv-queue-list] [data-test='sv-queue-item-#{last.id}']:first-child")
      )

    assert_eventually(fn ->
      %{results: items} = Engagement.list_queue(world.org, world.viewer, per_page: 100)
      Enum.map(items, & &1.video_id) == expected
    end)

    Map.put(world, :session, session)
  end

  when_ "I clear the queue", fn world ->
    session =
      world
      |> start_watching()
      |> Map.fetch!(:session)
      |> open_queue_panel()
      |> click(css("[data-test=clear-queue-btn]"))
      |> assert_gone(css("[data-test=clear-queue-btn]"))

    Map.put(world, :session, session)
  end

  then_ "all queue items are removed", fn world ->
    assert %{results: []} = Engagement.list_queue(world.org, world.viewer, per_page: 100)

    session =
      world.session
      |> visit_page(org_path(world, "/queue"))
      |> assert_has(css("[data-test=queue-panel]", text: "Your queue is empty"))
      |> assert_gone(css("[data-test=sv-queue-list]"))

    Map.put(world, :session, session)
  end

  given_ "I am watching a video and have items in my queue", fn world ->
    world
    |> seed_queue(2)
    |> start_watching()
  end

  when_ "I skip to the next video", fn world ->
    session = click(world.session, css("[data-test=skip-next-btn]"))
    Map.put(world, :session, session)
  end

  then_ "the next queued item begins playing", fn world ->
    [next | _] = world.queue_videos

    session =
      world.session
      |> assert_has(css("[data-test=sv-player][data-video-id='#{next.id}'][data-playback-id='#{next.mux_playback_id}']"))
      |> assert_has(css("[data-test=video-title]", text: next.title))

    Map.put(world, :session, session)
  end

  given_ "I have watched videos via the queue", fn world ->
    world = world |> seed_queue(1) |> start_watching()
    [next] = world.queue_videos

    session =
      world.session
      |> execute_script(ended_script())
      |> assert_has(css("[data-test=sv-player][data-video-id='#{next.id}']"))
      |> assert_has(css("[data-test=go-back-btn]"))

    Map.put(world, :session, session)
  end

  when_ "I click \"go back\"", fn world ->
    Map.put(world, :session, click(world.session, css("[data-test=go-back-btn]")))
  end

  then_ "the previously watched video resumes from the beginning", fn world ->
    session =
      world.session
      |> assert_has(css("[data-test=sv-player][data-video-id='#{world.video.id}'][data-resume-position='0.0']"))
      |> assert_has(css("[data-test=video-title]", text: world.video.title))

    Map.put(world, :session, session)
  end

  when_ "I add the collection to my queue", fn world ->
    session =
      world.session
      |> visit_page(org_path(world, "/collections/#{world.collection.slug}"))
      |> assert_has(css("[data-test=sv-collection-title]", text: world.collection.title))
      |> click(css("[data-test=sv-collection-add-to-queue]"))

    Map.put(world, :session, session)
  end

  then_ "the collection's videos are appended to my queue in order", fn world ->
    expected = Enum.map(world.videos, & &1.id)

    assert_eventually(fn ->
      %{results: items} = Engagement.list_queue(world.org, world.viewer, per_page: 100)
      Enum.map(items, & &1.video_id) == expected
    end)

    session =
      world.session
      |> visit_page(org_path(world, "/queue"))
      |> assert_has(css("[data-test=sv-queue-list]"))

    assert queue_dom_order(session, "sv-queue-item-") == expected
    Map.put(world, :session, session)
  end

  # ---- Video playback -----------------------------------------------------

  when_ "I navigate to the video watch page", fn world ->
    Map.put(world, :session, visit_watch(world, world.video))
  end

  then_ "the Mux player loads", fn world ->
    world.session
    |> assert_has(css("[data-test=sv-player][data-playback-id='#{world.video.mux_playback_id}'][data-video-id='#{world.video.id}']"))
    |> assert_has(css("[data-test=mux-player][playback-id='#{world.video.mux_playback_id}']"))

    world
  end

  then_ "playback begins", fn world ->
    world.session
    |> assert_has(css("[data-test=mux-player][autoplay]"))
    |> assert_has(css("[data-test=sv-player][data-resume-position='0.0']"))

    world
  end

  given_ "I am watching a video", fn world ->
    world
    |> Map.put(:video, ready_video(world.org, title: "Now playing"))
    |> start_watching()
  end

  when_ "I pause or stop at a certain position", fn world ->
    session = execute_script(world.session, pause_script(42.0))
    Map.merge(world, %{session: session, paused_at: 42.0})
  end

  then_ "my playback position is saved", fn world ->
    assert_eventually(fn ->
      case Engagement.get_progress(world.org, world.viewer, world.video) do
        %{position: position} -> position == world.paused_at
        _ -> false
      end
    end)

    world
  end

  given_ "I previously watched part of a video and my position was saved", fn world ->
    video = ready_video(world.org, title: "Half watched")

    insert(:progress,
      organization: world.org,
      user: nil,
      viewer: world.viewer,
      video: video,
      position: 120.0,
      duration: 600.0
    )

    Map.merge(world, %{video: video, saved_position: 120.0})
  end

  when_ "I open the video again", fn world ->
    Map.put(world, :session, visit_watch(world, world.video))
  end

  then_ "playback starts from my last saved position", fn world ->
    world.session
    |> assert_has(css("[data-test=sv-player][data-video-id='#{world.video.id}'][data-resume-position='#{world.saved_position}']"))

    world
  end

  given_ "I have partially watched a video that appears in my continue watching row", fn world ->
    video = ready_video(world.org, title: "Keep going")
    seed_continue_watching_row(world.org)

    insert(:progress,
      organization: world.org,
      user: nil,
      viewer: world.viewer,
      video: video,
      position: 90.0,
      duration: 600.0
    )

    session =
      world.session
      |> visit_page(org_path(world, "/"))
      |> assert_has(css("[data-test='dismiss-#{video.id}']"))

    Map.merge(world, %{session: session, video: video, saved_position: 90.0})
  end

  when_ "I click the dismiss button on that video's card", fn world ->
    session =
      world.session
      |> click(css("[data-test='dismiss-#{world.video.id}']"))
      |> assert_gone(css("[data-test='dismiss-#{world.video.id}']"))

    Map.put(world, :session, session)
  end

  then_ "the card is removed from my continue watching row", fn world ->
    session =
      world.session
      |> visit_page(org_path(world, "/"))
      |> assert_gone(css("[data-test='dismiss-#{world.video.id}']"))

    %{results: items} = Engagement.list_continue_watching(world.org, world.viewer)
    refute Enum.any?(items, &(&1[:video] && &1.video.id == world.video.id))

    Map.put(world, :session, session)
  end

  then_ "my playback progress for that video is not lost", fn world ->
    assert %{position: position, completed: false} =
             Engagement.get_progress(world.org, world.viewer, world.video)

    assert position == world.saved_position

    world
    |> visit_watch(world.video)
    |> assert_has(css("[data-test=sv-player][data-resume-position='#{world.saved_position}']"))

    world
  end

  given_ "I have dismissed a video from my continue watching row", fn world ->
    video = ready_video(world.org, title: "Dismissed once")
    seed_continue_watching_row(world.org)

    insert(:progress,
      organization: world.org,
      user: nil,
      viewer: world.viewer,
      video: video,
      position: 60.0,
      duration: 600.0
    )

    session =
      world.session
      |> visit_page(org_path(world, "/"))
      |> assert_has(css("[data-test='dismiss-#{video.id}']"))
      |> click(css("[data-test='dismiss-#{video.id}']"))
      |> assert_gone(css("[data-test='dismiss-#{video.id}']"))

    Map.merge(world, %{session: session, video: video})
  end

  when_ "I watch that video again", fn world ->
    # Dismissals and progress are stored at second precision, and the app
    # only resurfaces an item whose activity is strictly newer than the
    # dismissal. A real rewatch happens later than the dismissal second, so
    # wait for the clock to pass the persisted dismissed_at before watching.
    dismissed_at =
      Repo.get_by!(Marquee.Engagement.ContinueWatchingDismissal,
        viewer_id: world.viewer.id,
        video_id: world.video.id
      ).dismissed_at

    assert_eventually(fn ->
      DateTime.compare(DateTime.utc_now() |> DateTime.truncate(:second), dismissed_at) == :gt
    end)

    session =
      world
      |> visit_watch(world.video)
      |> execute_script(pause_script(200.0))

    assert_eventually(fn ->
      match?(%{position: 200.0}, Engagement.get_progress(world.org, world.viewer, world.video))
    end)

    Map.put(world, :session, session)
  end

  then_ "the video reappears in my continue watching row", fn world ->
    session =
      world.session
      |> visit_page(org_path(world, "/"))
      |> assert_has(css("[data-test='dismiss-#{world.video.id}']"))

    Map.put(world, :session, session)
  end

  given_ "I am watching an episode in a series", fn world ->
    built = build_series(world.org, seasons: 1, episodes: 2)
    [first_episode | _] = built.episodes
    seed_continue_watching_row(world.org)

    insert(:progress,
      organization: world.org,
      user: nil,
      viewer: world.viewer,
      video: first_episode.video,
      position: 45.0,
      duration: 600.0
    )

    session =
      world
      |> visit_watch(first_episode.video)
      |> assert_has(css("[data-test=series-breadcrumb]", text: built.series.title))

    Map.merge(world, %{
      session: session,
      series: built.series,
      season: built.season,
      episodes: built.episodes,
      video: first_episode.video,
      saved_position: 45.0
    })
  end

  given_ "the series appears in my continue watching row", fn world ->
    session =
      world.session
      |> visit_page(org_path(world, "/"))
      |> assert_has(css("[data-test='dismiss-#{world.series.id}']"))

    Map.put(world, :session, session)
  end

  when_ "I click the dismiss button on the series card", fn world ->
    session =
      world.session
      |> click(css("[data-test='dismiss-#{world.series.id}']"))
      |> assert_gone(css("[data-test='dismiss-#{world.series.id}']"))

    Map.put(world, :session, session)
  end

  then_ "the series no longer appears in my continue watching row", fn world ->
    session =
      world.session
      |> visit_page(org_path(world, "/"))
      |> assert_gone(css("[data-test='dismiss-#{world.series.id}']"))

    %{results: items} = Engagement.list_continue_watching(world.org, world.viewer)
    refute Enum.any?(items, &(&1[:series_id] == world.series.id))

    Map.put(world, :session, session)
  end

  then_ "my progress in the series is not lost", fn world ->
    assert %{position: position, completed: false} =
             Engagement.get_progress(world.org, world.viewer, world.video)

    assert position == world.saved_position
    world
  end

  when_ "the video plays to completion", fn world ->
    Map.put(world, :session, execute_script(world.session, ended_script()))
  end

  then_ "the video is marked as completed in my watch history", fn world ->
    assert_eventually(fn ->
      match?(%{completed: true}, Engagement.get_progress(world.org, world.viewer, world.video))
    end)

    assert_eventually(fn ->
      %{results: history} = Engagement.list_watch_history(world.org, world.viewer, per_page: 24)
      Enum.any?(history, &(&1.video_id == world.video.id))
    end)

    session =
      world.session
      |> visit_page(org_path(world, "/history"))
      |> assert_has(css("[data-test=sv-history-grid] [data-test='sv-card-#{world.video.id}']"))

    Map.put(world, :session, session)
  end

  when_ "I navigate to the series page", fn world ->
    session =
      world.session
      |> visit_page(org_path(world, "/series/#{world.series.slug}"))
      |> tolerate_autoplay_rejections()
    Map.put(world, :session, session)
  end

  then_ "I see the episode list", fn world ->
    session = assert_has(world.session, css("[data-test=episode-list]"))

    Enum.each(world.episodes, fn episode ->
      assert_has(session, css("[data-test='episode-row-#{episode.video.id}']", text: episode.video.title))
    end)

    Map.put(world, :session, session)
  end

  then_ "I can play individual episodes", fn world ->
    [_first, second | _] = world.episodes

    session =
      world.session
      |> click(css("[data-test='episode-link-#{second.video.id}']"))
      |> assert_has(css("[data-test=sv-player][data-video-id='#{second.video.id}'][data-playback-id='#{second.video.mux_playback_id}']"))
      |> assert_has(css("[data-test=video-title]", text: second.video.title))

    Map.put(world, :session, session)
  end

  when_ "I select a different season", fn world ->
    [_first_season, second_season] = world.seasons
    first_episode = hd(world.episodes)

    session =
      world.session
      |> visit_page(org_path(world, "/series/#{world.series.slug}"))
      |> tolerate_autoplay_rejections()
      |> assert_has(css("[data-test='episode-row-#{first_episode.video.id}']"))
      |> select_option("[data-test=season-selector] select", second_season.id)

    Map.merge(world, %{session: session, selected_season: second_season})
  end

  then_ "the episode list updates to show episodes for that season", fn world ->
    season_episodes = Content.list_episodes(world.org, world.selected_season)
    assert season_episodes != []

    session = world.session

    Enum.each(season_episodes, fn episode ->
      assert_has(session, css("[data-test='episode-row-#{episode.video.id}']"))
    end)

    Enum.each(world.episodes, fn episode ->
      assert_gone(session, css("[data-test='episode-row-#{episode.video.id}']"))
    end)

    world
  end

  # ---- Watch history ------------------------------------------------------

  given_ "I have watched videos in the past", fn world ->
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    videos =
      for {hours_ago, index} <- Enum.with_index([1, 24, 72]) do
        video = ready_video(world.org, title: "Watched #{index}")

        insert(:watch_history,
          organization: world.org,
          user: nil,
          viewer: world.viewer,
          video: video,
          watched_at: DateTime.add(now, -hours_ago, :hour)
        )

        video
      end

    Map.put(world, :history_videos, videos)
  end

  when_ "I navigate to /history", fn world ->
    Map.put(world, :session, visit_page(world.session, org_path(world, "/history")))
  end

  then_ "I see a chronological list of videos I have watched", fn world ->
    session = assert_has(world.session, css("[data-test=sv-history-grid]"))
    expected = Enum.map(world.history_videos, & &1.id)

    assert history_dom_order(session) == expected
    Map.put(world, :session, session)
  end

  given_ "I have a long watch history spanning more than one page", fn world ->
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    videos =
      for index <- 1..25 do
        video = ready_video(world.org, title: "History #{index}")

        insert(:watch_history,
          organization: world.org,
          user: nil,
          viewer: world.viewer,
          video: video,
          watched_at: DateTime.add(now, -index, :minute)
        )

        video
      end

    Map.put(world, :history_videos, videos)
  end

  when_ "I reach the bottom of the history list", fn world ->
    session =
      world.session
      |> visit_page(org_path(world, "/history"))
      |> assert_has(css("[data-test=sv-history-grid]"))

    assert_eventually(fn -> length(card_video_ids(session, "[data-test=sv-history-grid]")) == 24 end)

    session =
      session
      |> execute_script("window.scrollTo(0, document.body.scrollHeight); return true;")
      |> click(css("[data-test=load-more-btn]"))

    Map.put(world, :session, session)
  end

  then_ "more history items are loaded", fn world ->
    session = world.session

    assert_eventually(fn ->
      card_video_ids(session, "[data-test=sv-history-grid]") == Enum.map(world.history_videos, & &1.id)
    end)

    # Every entry is now shown, so there is nothing left to load.
    assert_gone(session, css("[data-test=load-more-btn]"))

    Map.put(world, :session, session)
  end

  given_ "a video appears in my watch history with a saved position", fn world ->
    video = ready_video(world.org, title: "Resume me")

    insert(:watch_history, organization: world.org, user: nil, viewer: world.viewer, video: video)

    insert(:progress,
      organization: world.org,
      user: nil,
      viewer: world.viewer,
      video: video,
      position: 75.0,
      duration: 600.0
    )

    Map.merge(world, %{video: video, saved_position: 75.0})
  end

  when_ "I click on it from history", fn world ->
    session =
      world.session
      |> visit_page(org_path(world, "/history"))
      |> click(css("[data-test=sv-history-grid] [data-test='sv-card-#{world.video.id}']"))
      |> await_live_connect()

    Map.put(world, :session, session)
  end

  then_ "playback resumes from my last saved position", fn world ->
    world.session
    |> assert_has(css("[data-test=sv-player][data-video-id='#{world.video.id}'][data-resume-position='#{world.saved_position}']"))

    world
  end

  # ---- Watchlist and favorites --------------------------------------------

  when_ "I add it to my watchlist", fn world ->
    case world do
      %{series: series} ->
        session =
          world.session
          |> visit_page(org_path(world, "/series/#{series.slug}"))
          |> assert_has(css("[data-test=series-breadcrumb]", text: series.title))
          |> click(css("[data-test=series-watchlist-btn]"))
          |> assert_has(css("[data-test=series-watchlist-btn][aria-pressed='true']"))

        Map.put(world, :session, session)

      %{video: video} ->
        session =
          world.session
          |> visit_page(org_path(world, "/browse"))
          |> click(css("[data-test='sv-card-watchlist-#{video.id}']"))
          |> assert_has(css("[data-test='sv-card-watchlist-#{video.id}'][aria-pressed='true']"))

        Map.put(world, :session, session)
    end
  end

  then_ "it appears in my watchlist at /watchlist", fn world ->
    assert Engagement.in_watchlist?(world.org, world.viewer, world.video)

    session =
      world.session
      |> visit_page(org_path(world, "/watchlist"))
      |> assert_has(css("[data-test=sv-watchlist-grid] [data-test='sv-watchlist-remove-#{world.video.id}']"))

    Map.put(world, :session, session)
  end

  then_ "it appears in my watchlist", fn world ->
    assert Engagement.in_watchlist?(world.org, world.viewer, world.series)

    session =
      world.session
      |> visit_page(org_path(world, "/watchlist"))
      |> assert_has(css("[data-test=sv-watchlist-grid] [data-test='sv-watchlist-remove-series-#{world.series.id}']"))

    Map.put(world, :session, session)
  end

  given_ "an item is in my watchlist", fn world ->
    video = ready_video(world.org, title: "Saved for later")
    {:ok, _item} = Engagement.add_to_watchlist(world.org, world.viewer, video)
    Map.put(world, :video, video)
  end

  when_ "I remove it", fn world ->
    session =
      world.session
      |> visit_page(org_path(world, "/watchlist"))
      |> click(css("[data-test='sv-watchlist-remove-#{world.video.id}']"))
      |> assert_gone(css("[data-test='sv-watchlist-remove-#{world.video.id}']"))

    Map.put(world, :session, session)
  end

  then_ "it no longer appears in my watchlist", fn world ->
    refute Engagement.in_watchlist?(world.org, world.viewer, world.video)

    session =
      world.session
      |> visit_page(org_path(world, "/watchlist"))
      |> assert_gone(css("[data-test='sv-watchlist-remove-#{world.video.id}']"))

    Map.put(world, :session, session)
  end

  when_ "I mark it as a favorite", fn world ->
    session =
      world.session
      |> visit_page(org_path(world, "/browse"))
      |> click(css("[data-test='sv-card-favorite-#{world.video.id}']"))
      |> assert_has(css("[data-test='sv-card-favorite-#{world.video.id}'][aria-pressed='true']"))

    Map.put(world, :session, session)
  end

  then_ "it appears in my favorites at /favorites", fn world ->
    assert Engagement.favorited?(world.org, world.viewer, world.video)

    session =
      world.session
      |> visit_page(org_path(world, "/favorites"))
      |> assert_has(css("[data-test=sv-favorites-grid] [data-test='sv-card-#{world.video.id}']"))

    Map.put(world, :session, session)
  end

  given_ "a video is in my favorites", fn world ->
    video = ready_video(world.org, title: "Loved it")
    {:ok, _id, :added} = Engagement.toggle_favorite(world.org, world.viewer, video)
    Map.put(world, :video, video)
  end

  when_ "I remove it from favorites", fn world ->
    session =
      world.session
      |> visit_page(org_path(world, "/favorites"))
      |> click(css("[data-test='sv-favorite-remove-#{world.video.id}']"))
      |> assert_gone(css("[data-test='sv-favorite-remove-#{world.video.id}']"))

    Map.put(world, :session, session)
  end

  then_ "it is removed from /favorites", fn world ->
    refute Engagement.favorited?(world.org, world.viewer, world.video)

    session =
      world.session
      |> visit_page(org_path(world, "/favorites"))
      |> assert_gone(css("[data-test='sv-card-#{world.video.id}']"))

    Map.put(world, :session, session)
  end

  # ---- Helpers ------------------------------------------------------------

  # Signs a subscribed viewer of `world.org` (created if missing) in through
  # a magic link; gated viewer routes (/watch, /queue, /watchlist, /history)
  # need an active subscription.
  defp log_in_viewer(world) do
    org = Map.get_lazy(world, :org, fn -> insert(:organization) end)
    viewer = insert(:subscribed_viewer, organization: org)
    {encoded_token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
    Repo.insert!(viewer_token)

    session =
      world.session
      |> visit_page("/magic-link/#{encoded_token}?org=#{org.slug}")
      |> assert_has(css("[data-test=viewer-sign-out]"))

    Map.merge(world, %{org: org, viewer: viewer, session: session})
  end

  # The suite runs Chrome with `pageLoadStrategy: "none"`, so `visit/2`
  # returns before the new document replaces the current one and a
  # `.phx-connected` check can still match the previous page. Tag the
  # current document, wait for a document without the tag, then wait for
  # the new page's LiveView to join.
  defp visit_page(session, path) do
    session
    |> execute_script("document.documentElement.setAttribute('data-cc-stale', ''); return true;")
    |> visit(path)
    |> assert_gone(css("html[data-cc-stale]"))
    |> await_live_connect()
  end

  # Wallaby's `refute_has/2` checks once and fails if an element is still
  # there, which races LiveView patches. Waiting for a count of zero retries
  # until the element is gone (or Wallaby's max wait elapses).
  defp assert_gone(session, %Wallaby.Query{} = query) do
    assert_has(session, %{query | conditions: Keyword.put(query.conditions, :count, 0)})
  end

  defp ensure_viewer_session(%{viewer: _} = world), do: world
  defp ensure_viewer_session(world), do: log_in_viewer(world)

  defp org_path(world, path) do
    separator = if String.contains?(path, "?"), do: "&", else: "?"
    "#{path}#{separator}org=#{world.org.slug}"
  end

  defp ready_video(org, attrs) do
    insert(
      :video,
      Keyword.merge(
        [organization: org, mux_status: "ready", published: true, duration: 600.0],
        attrs
      )
    )
  end

  defp build_series(org, seasons: season_count, episodes: episodes_per_season) do
    series = insert(:series, organization: org, title: "Test Series")

    seasons =
      for season_number <- 1..season_count do
        insert(:season,
          organization: org,
          series: series,
          season_number: season_number,
          title: "Season #{season_number}",
          episode_count: episodes_per_season
        )
      end

    episodes_by_season =
      Map.new(seasons, fn season ->
        episodes =
          for episode_number <- 1..episodes_per_season do
            video = ready_video(org, title: "S#{season.season_number}E#{episode_number}")

            insert(:episode,
              organization: org,
              season: season,
              video: video,
              episode_number: episode_number
            )
          end

        {season.id, episodes}
      end)

    first_season = hd(seasons)

    %{
      series: series,
      season: first_season,
      seasons: seasons,
      episodes: Map.fetch!(episodes_by_season, first_season.id)
    }
  end

  defp seed_queue(world, count) do
    videos =
      for index <- 0..(count - 1) do
        video = ready_video(world.org, title: "Queued #{index}")
        {:ok, _item} = Engagement.add_to_queue(world.org, world.viewer, video)
        video
      end

    Map.put(world, :queue_videos, videos)
  end

  # Opens the watch page for `world.video` (created if missing) and waits for
  # the player container to mount.
  defp start_watching(world) do
    video = Map.get_lazy(world, :video, fn -> ready_video(world.org, title: "Now playing") end)
    Map.merge(world, %{video: video, session: visit_watch(world, video)})
  end

  defp visit_watch(%{session: session} = world, video) do
    visit_watch(session, org_path(world, "/watch/#{video.id}"), video)
  end

  defp visit_watch(session, path, video) do
    session
    |> visit_page(path)
    |> assert_has(css("[data-test=sv-player][data-video-id='#{video.id}']"))
    |> tolerate_autoplay_rejections()
  end

  # Swapping the player source (queue advance, episode/season switch, go
  # back) makes <mux-player> call play(), which headless Chrome rejects under
  # its autoplay policy (NotAllowedError) or aborts when the next source
  # loads (AbortError). No media is served in tests, so those rejections are
  # environmental; Wallaby would otherwise fail the step on the uncaught
  # promise. Only those two play() rejections are silenced: every other
  # uncaught error still fails the scenario.
  defp tolerate_autoplay_rejections(session) do
    execute_script(session, """
    window.addEventListener('unhandledrejection', (event) => {
      const reason = event.reason;
      if (reason instanceof DOMException &&
          ['NotAllowedError', 'AbortError'].includes(reason.name) &&
          /play\(\)/.test(reason.message)) {
        event.preventDefault();
      }
    });
    return true;
    """)
  end

  # The chevron toggle is revealed while the pointer is over the player.
  defp open_queue_panel(session) do
    session
    |> hover(css("[data-test=sv-player]"))
    |> click(css("[data-test=queue-chevron-toggle][aria-label='Open queue']"))
    |> assert_has(css("[data-test=queue-chevron-toggle][aria-label='Close queue']"))
    |> assert_has(css("[data-test=queue-panel] [data-test=queue-list]"))
  end

  defp seed_continue_watching_row(org) do
    insert(:row, organization: org, title: "Continue watching", source_type: :continue_watching, position: 0)
  end

  defp queue_dom_order(session, prefix) do
    session
    |> all(css("[data-test^='#{prefix}']"))
    |> Enum.map(&String.replace_prefix(Wallaby.Element.attr(&1, "data-test"), prefix, ""))
  end

  defp history_dom_order(session), do: card_video_ids(session, "[data-test=sv-history-grid]")

  # Video ids of the content cards (`data-test="sv-card-<uuid>"`) inside
  # `scope`, in DOM order. A prefix selector alone would also match the
  # cards' own action buttons (`sv-card-favorite-<uuid>`, ...).
  @card_test_id ~r/^sv-card-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/

  defp card_video_ids(session, scope) do
    session
    |> all(css("#{scope} [data-test^='sv-card-']"))
    |> Enum.flat_map(fn element ->
      case Regex.run(@card_test_id, Wallaby.Element.attr(element, "data-test") || "") do
        [_, id] -> [id]
        _ -> []
      end
    end)
  end

  # The MuxPlayer hook reads `currentTime` off the <mux-player> element when
  # it hears `pause`; pin the position on the element, then fire the event.
  defp pause_script(position) do
    """
    const player = document.querySelector('[data-test=mux-player]');
    Object.defineProperty(player, 'currentTime', {value: #{position}, configurable: true, writable: true});
    player.dispatchEvent(new Event('pause'));
    return true;
    """
  end

  defp ended_script do
    """
    const player = document.querySelector('[data-test=mux-player]');
    player.dispatchEvent(new Event('ended'));
    return true;
    """
  end

  # Drives Sortable.js through the native HTML5 drag-and-drop event sequence
  # it listens for: mousedown on the handle, dragstart on the item, dragover
  # on the drop target, then drop/dragend so `onEnd` pushes `reorder_queue`.
  defp drag_script(list_selector, dragged_video_id, target_video_id) do
    """
    const list = document.querySelector('#{list_selector}');
    const src = list.querySelector("[data-id='#{dragged_video_id}']");
    const dst = list.querySelector("[data-id='#{target_video_id}']");
    const handle = src.querySelector('.sv-queue-drag-handle');
    const dt = new DataTransfer();
    const rect = (el) => el.getBoundingClientRect();
    const drag = (el, type, x, y) =>
      el.dispatchEvent(new DragEvent(type, {bubbles: true, cancelable: true, clientX: x, clientY: y, dataTransfer: dt}));
    const s = rect(handle);
    const sx = s.left + 2, sy = s.top + 2;
    // Sortable listens for pointerdown where PointerEvent is supported.
    handle.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true, cancelable: true, clientX: sx, clientY: sy, button: 0, isPrimary: true, pointerType: 'mouse'}));
    setTimeout(() => {
      drag(src, 'dragstart', sx, sy);
      setTimeout(() => {
        const d = rect(dst);
        const dx = d.left + d.width / 2, dy = d.top + 2;
        drag(dst, 'dragenter', dx, dy);
        drag(dst, 'dragover', dx, dy);
        drag(dst, 'dragover', dx, dy + 1);
        setTimeout(() => {
          drag(dst, 'drop', dx, dy);
          drag(src, 'dragend', dx, dy);
        }, 50);
      }, 50);
    }, 50);
    return true;
    """
  end

  defp assert_eventually(fun, attempts \\ 40) do
    if fun.() do
      :ok
    else
      if attempts <= 1 do
        flunk("condition not met before timeout")
      else
        Process.sleep(100)
        assert_eventually(fun, attempts - 1)
      end
    end
  end
end
