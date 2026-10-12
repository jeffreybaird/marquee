defmodule MarqueeFeatures.Steps.ShortFormFeed do
  @moduledoc """
  Acceptance steps for the vertical Shorts feed (viewer `/shorts`) and its
  operator management page (`/admin/shorts`).

  Like the other step modules these drive the real browser session in
  `world.session` (see `features/support/env.ex`); data is set up through
  factories and context functions. Assertions stay on server-rendered DOM
  states (locked calls to action, navigation, clip articles, has-more/end,
  admin rows and flashes); playback itself is covered by the Wallaby suite.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query, only: [css: 1, css: 2]
  import Marquee.Factory
  import ExUnit.Assertions

  alias Marquee.Accounts.{Organization, Scope}
  alias Marquee.{Content, Engagement, Repo, Viewers}
  alias Marquee.Viewers.ViewerToken

  # ---- Viewer-side setup ---------------------------------------------------

  given_("an organization whose Shorts feed is enabled with access {string}", fn world, access ->
    org = insert(:organization, shorts_feed_enabled: true, shorts_feed_access: access)
    Map.merge(world, %{shorts_org: org, shorts_videos: []})
  end)

  given_("an organization whose Shorts feed is disabled", fn world ->
    org = insert(:organization, shorts_feed_enabled: false)
    seed_shorts(org, 1, [])
    Map.merge(world, %{shorts_org: org, shorts_videos: []})
  end)

  given_("the Shorts feed contains {int} ready clips", fn world, count ->
    Map.put(world, :shorts_videos, seed_shorts(world.shorts_org, count, []))
  end)

  given_(
    "the Shorts feed contains {int} ready clips with video visibility {string}",
    fn world, count, visibility ->
      videos = seed_shorts(world.shorts_org, count, visibility: visibility)
      Map.put(world, :shorts_videos, videos)
    end
  )

  given_("a Shorts viewer with subscription status {string} is signed in", fn world, status ->
    viewer = insert(:viewer, organization: world.shorts_org, subscription_status: status)
    sign_in_viewer(world, viewer)
  end)

  given_("a Shorts viewer granted complimentary access is signed in", fn world ->
    viewer = insert(:viewer, organization: world.shorts_org, subscription_status: "none")
    {:ok, granted} = Viewers.grant_access(shorts_scope(world.shorts_org, :owner), viewer)
    sign_in_viewer(world, granted)
  end)

  given_("only the first Shorts clip belongs to the subscriber demo catalog", fn world ->
    [first | _] = world.shorts_videos

    org =
      world.shorts_org
      |> Ecto.Changeset.change(
        features: %{"subscriber_demo" => true, "subscriber_demo_video_ids" => [first.id]}
      )
      |> Repo.update!()

    Map.put(world, :shorts_org, org)
  end)

  given_("a subscriber demo viewer of the Shorts organization is signed in", fn world ->
    expires = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601()

    viewer =
      insert(:subscribed_viewer,
        organization: world.shorts_org,
        metadata: %{"subscriber_demo" => true, "subscriber_demo_expires_at" => expires}
      )

    sign_in_viewer(world, viewer)
  end)

  given_("another organization has a Shorts clip titled {string}", fn world, title ->
    other = insert(:organization, shorts_feed_enabled: true, shorts_feed_access: "public")
    [video] = seed_shorts(other, 1, title: title)
    Map.put(world, :rival_short, video)
  end)

  # ---- Viewer-side actions -------------------------------------------------

  when_("a signed-out visitor opens the browse page of the Shorts organization", fn world ->
    session =
      world.session
      |> visit("/browse?org=#{world.shorts_org.slug}")
      |> assert_has(css("[data-test=sv-root]"))

    Map.put(world, :session, session)
  end)

  when_("the visitor opens the Shorts feed", fn world ->
    # The feed renders either clips in #shorts-feed or the empty state; check
    # DOM presence rather than Wallaby visibility.
    session =
      world.session
      |> visit("/shorts?org=#{world.shorts_org.slug}")
      |> wait_for_live_view()

    eventually("the Shorts page", fn ->
      dom_count(session, "#shorts-feed[role=feed], [data-test=shorts-empty]") >= 1
    end)

    Map.put(world, :session, session)
  end)

  when_("the visitor nears the end of the loaded Shorts clips", fn world ->
    # Bring the last loaded clip into view; the ShortsFeed hook asks the
    # server for the next page once the active clip is near the end.
    eval(world.session, """
    const clips = document.querySelectorAll('#shorts-feed article');
    clips[clips.length - 1].scrollIntoView({block: 'start', behavior: 'auto'});
    return true;
    """)

    world
  end)

  when_("the viewer favorites the first Shorts clip", fn world ->
    [first | _] = world.shorts_videos
    session = click(world.session, css("[data-test='short-favorite-#{first.id}']"))
    Map.put(world, :session, session)
  end)

  # ---- Viewer-side assertions ----------------------------------------------

  then_("the Shorts navigation link is visible", fn world ->
    assert_has(world.session, css("[data-test=nav-shorts][href='/shorts']"))
    world
  end)

  then_("the Shorts navigation link is not visible", fn world ->
    assert dom_count(world.session, "[data-test=nav-shorts]") == 0
    world
  end)

  then_("opening the Shorts feed sends the visitor to the home page", fn world ->
    session = visit(world.session, "/shorts?org=#{world.shorts_org.slug}")
    eventually("redirect to the home page", fn -> current_path(session) == "/" end)
    assert dom_count(session, "#shorts-feed") == 0
    Map.put(world, :session, session)
  end)

  then_("the Shorts empty state is shown", fn world ->
    assert_has(world.session, css("[data-test=shorts-empty]"))
    assert dom_count(world.session, "#shorts-feed article") == 0
    world
  end)

  then_("{int} Shorts clips are listed", fn world, count ->
    eventually("#{count} Shorts clips", fn ->
      dom_count(world.session, "#shorts-feed article") == count
    end)

    world
  end)

  then_("the end of the Shorts feed is shown", fn world ->
    eventually("the end of the feed", fn ->
      dom_count(world.session, "#shorts-feed[data-has-more='false']") == 1 and
        dom_count(world.session, "[data-test=shorts-end]") == 1
    end)

    world
  end)

  then_("every Shorts clip is playable", fn world ->
    for video <- world.shorts_videos do
      selector =
        "article[data-video-id='#{video.id}'][data-playback-id='#{video.mux_playback_id}']"

      assert dom_count(world.session, selector) == 1
      assert dom_count(world.session, "[data-test='short-locked-#{video.id}']") == 0
    end

    world
  end)

  then_("every Shorts clip is locked with a call to action to {string}", fn world, href ->
    for video <- world.shorts_videos do
      locked = "[data-test='short-locked-#{video.id}']"
      assert dom_count(world.session, locked) == 1

      assert dom_count(world.session, "#{locked} a[href='#{href}']") +
               dom_count(world.session, "a#{locked}[href='#{href}']") >= 1,
             "expected a #{href} call to action on locked clip #{video.id}"
    end

    world
  end)

  then_("no Shorts playback id or Mux image is exposed", fn world ->
    source = page_source(world.session)
    refute source =~ "image.mux.com"

    for video <- world.shorts_videos do
      refute source =~ video.mux_playback_id

      assert dom_count(world.session, "article[data-video-id='#{video.id}'][data-playback-id]") ==
               0
    end

    world
  end)

  then_("only the first Shorts clip is listed", fn world ->
    [first | rest] = world.shorts_videos
    assert dom_count(world.session, "article[data-video-id='#{first.id}']") == 1
    source = page_source(world.session)

    for video <- rest do
      assert dom_count(world.session, "article[data-video-id='#{video.id}']") == 0
      refute source =~ video.mux_playback_id
    end

    world
  end)

  then_("the first Shorts clip is saved as a favorite", fn world ->
    [first | _] = world.shorts_videos

    assert_has(
      world.session,
      css("[data-test='short-favorite-#{first.id}'][aria-pressed='true']")
    )

    assert Engagement.favorited?(world.shorts_org, world.shorts_viewer, first)
    world
  end)

  then_("the Shorts feed does not include {string}", fn world, title ->
    refute page_source(world.session) =~ title
    assert dom_count(world.session, "article[data-video-id='#{world.rival_short.id}']") == 0
    world
  end)

  # ---- Operator-side setup -------------------------------------------------

  given_("a ready video titled {string} is available for Shorts", fn world, title ->
    video = insert(:video, organization: world.org, title: title, mux_status: "ready")
    Map.update(world, :shorts_named, %{title => video}, &Map.put(&1, title, video))
  end)

  given_("a processing video titled {string} is available for Shorts", fn world, title ->
    video = insert(:video, organization: world.org, title: title, mux_status: "preparing")
    Map.update(world, :shorts_named, %{title => video}, &Map.put(&1, title, video))
  end)

  given_("another organization has a ready video titled {string}", fn world, title ->
    video =
      insert(:video, organization: insert(:organization), title: title, mux_status: "ready")

    Map.update(world, :shorts_named, %{title => video}, &Map.put(&1, title, video))
  end)

  given_("the Shorts feed already lists {string} then {string}", fn world, first, second ->
    scope = shorts_scope(world.org, :editor)

    named =
      for title <- [first, second], into: %{} do
        video = insert(:video, organization: world.org, title: title, mux_status: "ready")
        {:ok, item} = Content.add_short_feed_video(scope, video)
        {title, %{video: video, item: item}}
      end

    Map.put(world, :shorts_items, named)
  end)

  given_("the Shorts video {string} has since failed processing", fn world, title ->
    %{video: video} = Map.fetch!(world.shorts_items, title)
    {:ok, _} = Content.mark_video_errored(video.mux_asset_id, %{})
    world
  end)

  # ---- Operator-side actions -----------------------------------------------

  when_("I open the Shorts management page", fn world ->
    Map.put(world, :session, open_admin_shorts(world))
  end)

  when_("I switch the Shorts feed on", fn world ->
    session =
      world.session
      |> click(css("[data-test=shorts-enabled-toggle]"))
      |> assert_has(css("[data-test=shorts-enabled-toggle][aria-checked='true']"))

    Map.put(world, :session, session)
  end)

  when_("I set Shorts access to {string}", fn world, access ->
    session = click(world.session, css("#shorts-access-#{access}"))

    eventually("access saved as #{access}", fn ->
      Repo.get!(Organization, world.org.id).shorts_feed_access == access
    end)

    Map.put(world, :session, session)
  end)

  when_("I open the Shorts video picker", fn world ->
    session =
      world.session
      |> click(css("[data-test=shorts-open-picker]"))
      |> assert_has(css("[data-test=shorts-picker-search]"))

    Map.put(world, :session, session)
  end)

  when_("I add {string} from the Shorts video picker", fn world, title ->
    video = Map.fetch!(world.shorts_named, title)

    session =
      world.session
      |> click(css("[data-test=shorts-open-picker]"))
      |> click(css("[data-test='shorts-add-#{video.id}']"))

    Map.put(world, :session, session)
  end)

  when_("I move {string} up in the Shorts feed", fn world, title ->
    %{item: item} = Map.fetch!(world.shorts_items, title)
    session = click(world.session, css("[data-test='shorts-move-up-#{item.id}']"))
    Map.put(world, :session, session)
  end)

  when_("I remove {string} from the Shorts feed", fn world, title ->
    %{item: item} = Map.fetch!(world.shorts_items, title)
    session = click(world.session, css("[data-test='shorts-remove-#{item.id}']"))
    Map.put(world, :session, session)
  end)

  # ---- Operator-side assertions --------------------------------------------

  then_("the Shorts feed is enabled with access {string}", fn world, access ->
    org = Repo.get!(Organization, world.org.id)
    assert org.shorts_feed_enabled == true
    assert org.shorts_feed_access == access

    assert_has(world.session, css("[data-test=shorts-enabled-toggle][aria-checked='true']"))
    world
  end)

  then_("the Shorts feed lists {string}", fn world, title ->
    eventually("#{title} in the feed", fn -> admin_feed_titles(world.org) == [title] end)
    [item] = Content.list_short_feed_items(world.org).results
    assert_has(world.session, css("[data-test='shorts-item-#{item.id}']", text: title))
    world
  end)

  then_("{string} is not offered in the Shorts video picker", fn world, title ->
    video = Map.fetch!(world.shorts_named, title)
    assert dom_count(world.session, "[data-test='shorts-picker-video-#{video.id}']") == 0
    assert dom_count(world.session, "[data-test='shorts-add-#{video.id}']") == 0
    refute page_source(world.session) =~ title
    world
  end)

  then_("the Shorts feed lists {string} before {string}", fn world, first, second ->
    eventually("#{first} before #{second}", fn ->
      admin_feed_titles(world.org) == [first, second]
    end)

    world
  end)

  then_("the Shorts feed no longer lists {string}", fn world, title ->
    %{item: item} = Map.fetch!(world.shorts_items, title)
    eventually("#{title} removed", fn -> title not in admin_feed_titles(world.org) end)
    refute_has(world.session, css("[data-test='shorts-item-#{item.id}']"))
    world
  end)

  then_("no Shorts management controls are available", fn world ->
    session = world.session

    for {_title, %{item: item}} <- world.shorts_items do
      assert_has(session, css("[data-test='shorts-item-#{item.id}']"))

      for control <- ["shorts-remove", "shorts-move-up", "shorts-move-down"] do
        assert dom_count(session, "[data-test='#{control}-#{item.id}']") == 0
      end
    end

    for id <- ["shorts-enabled-toggle", "shorts-access-form", "shorts-open-picker"] do
      assert dom_count(session, "[data-test=#{id}]") == 0
    end

    world
  end)

  then_("a forced Shorts change is refused and nothing changes", fn world ->
    before_titles = admin_feed_titles(world.org)
    before_org = Repo.get!(Organization, world.org.id)
    %{item: item} = world.shorts_items |> Map.values() |> List.first()

    # The controls are absent, so push the events straight over the socket.
    session = force_event(world.session, "remove_item", %{"id" => item.id})
    assert_has(session, css("#flash-error"))

    # A fresh page so the second refusal must raise its own flash.
    session = open_admin_shorts(%{world | session: session})
    assert dom_count(session, "#flash-error") == 0
    session = force_event(session, "toggle_enabled", %{})
    assert_has(session, css("#flash-error"))

    assert admin_feed_titles(world.org) == before_titles
    after_org = Repo.get!(Organization, world.org.id)
    assert after_org.shorts_feed_enabled == before_org.shorts_feed_enabled
    Map.put(world, :session, session)
  end)

  then_("{string} is badged Unavailable in the Shorts feed", fn world, title ->
    %{item: item} = Map.fetch!(world.shorts_items, title)

    assert_has(
      world.session,
      css("[data-test='shorts-item-status-#{item.id}']", text: "Unavailable")
    )

    world
  end)

  then_("{string} is badged Ready in the Shorts feed", fn world, title ->
    %{item: item} = Map.fetch!(world.shorts_items, title)
    assert_has(world.session, css("[data-test='shorts-item-status-#{item.id}']", text: "Ready"))
    world
  end)

  then_("the Shorts management empty state is shown", fn world ->
    assert_has(world.session, css("[data-test=shorts-admin-empty]"))
    world
  end)

  # ---- Helpers ---------------------------------------------------------------

  defp shorts_scope(org, role) do
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: role)
    Scope.for_user(user) |> Scope.with_organization(org, membership)
  end

  defp seed_shorts(org, count, attrs) do
    scope = shorts_scope(org, :editor)

    for n <- 1..count do
      video =
        insert(
          :video,
          Keyword.merge(
            [
              organization: org,
              title: "Short clip #{n}",
              mux_status: "ready",
              mux_playback_id: "pbshort#{n}x#{System.unique_integer([:positive])}",
              duration: 20.0,
              aspect_ratio: "9:16"
            ],
            attrs
          )
        )

      {:ok, _item} = Content.add_short_feed_video(scope, video)
      video
    end
  end

  # Viewers sign in through a magic link; the controller sets the viewer
  # session cookie and redirects to the org home.
  defp sign_in_viewer(world, viewer) do
    {encoded_token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
    Repo.insert!(viewer_token)

    session =
      world.session
      |> visit("/magic-link/#{encoded_token}?org=#{world.shorts_org.slug}")
      |> assert_has(css("[data-test=sv-root]"))

    Map.merge(world, %{session: session, shorts_viewer: viewer})
  end

  defp open_admin_shorts(world) do
    world.session
    |> visit("/admin/shorts?org=#{world.org.slug}")
    |> assert_has(css("[data-test=admin-nav-shorts][aria-current=page]"))
    |> wait_for_live_view()
  end

  # Hooks and event bindings are live once the root is marked connected.
  defp wait_for_live_view(session) do
    assert_has(session, css("[data-phx-main].phx-connected"))
  end

  defp force_event(session, event, value) do
    eval(
      session,
      """
      const main = document.querySelector('[data-phx-main]');
      window.liveSocket.execJS(main, JSON.stringify([["push", {event: arguments[0], value: arguments[1]}]]));
      return true;
      """,
      [event, value]
    )

    session
  end

  defp dom_count(session, selector) do
    eval(session, "return document.querySelectorAll(arguments[0]).length;", [selector])
  end

  defp eval(session, script, args \\ []) do
    ref = make_ref()
    execute_script(session, script, args, fn value -> send(self(), {ref, value}) end)

    receive do
      {^ref, value} -> value
    after
      5_000 -> flunk("browser did not return a script result")
    end
  end

  # Polls until `check` passes; a browser round-trip has no synchronous
  # completion signal to wait on (precedent: MarqueeWeb.WallabyCase).
  defp eventually(description, check, timeout_ms \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_eventually(description, check, deadline)
  end

  defp do_eventually(description, check, deadline) do
    cond do
      check.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("timed out waiting for #{description}")

      true ->
        Process.sleep(50)
        do_eventually(description, check, deadline)
    end
  end

  defp admin_feed_titles(org) do
    org
    |> Content.list_short_feed_items(per_page: 100)
    |> Map.fetch!(:results)
    |> Enum.map(& &1.video.title)
  end
end
