defmodule MarqueeWeb.E2E.ViewerShortsFeedTest do
  @moduledoc """
  Browser coverage for the viewer Shorts feed (`/shorts`, issue #16).

  LiveViewTest cannot run the `ShortsFeed` hook, the IntersectionObserver
  that picks the active clip, keyboard handling, or the autoplay fallback, so
  these scenarios drive real Chrome.

  No Mux network is needed: `open_feed/3` loads the org home, waits for the
  LiveView to connect, runs `stub_players/2` and only then live-navigates to
  `/shorts` through the nav item, so every Shorts player is created from the
  stubbed prototype in the same JS realm. `stub_players/2` replaces `play`/`pause`/`paused`/`muted` on the `<mux-player>` element
  prototype (defining a bare element if the vendored player bundle is not
  registered). The stub records state on each player as
  `data-e2e-state="playing" | "paused"` and the number of `play()` calls as
  `data-e2e-play-calls`; in `"blocked"` mode every `play()` rejects with a
  `NotAllowedError`, the way an autoplay policy does. A capture-phase
  `window` listener swallows `error` events from `<mux-player>` elements so a
  real player bundle cannot flip clips into the error state over the network.
  """
  use MarqueeWeb.WallabyCase

  alias Marquee.Accounts.Scope
  alias Marquee.Content
  alias Marquee.Repo
  alias Marquee.Viewers.ViewerToken

  @moduletag :e2e

  @mobile {390, 844}
  @desktop {1280, 900}

  # Two viewer pages: the feed's default page size is 8.
  @clip_count 12

  # Clip 1 (index 0) is portrait 9:16, clip 2 (index 1) is landscape 16:9.
  defp aspect_ratio_for(2), do: "16:9"
  defp aspect_ratio_for(_index), do: "9:16"

  setup %{session: session} do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

    {:ok, org} =
      Content.update_short_feed_settings(scope, %{enabled: true, access: "subscribers_only"})

    scope = Scope.with_organization(scope, org, membership)

    for index <- 1..@clip_count do
      video =
        insert(:video,
          organization: org,
          title: "Short clip #{index}",
          mux_status: "ready",
          mux_playback_id: "e2e-shorts-playback-#{index}",
          aspect_ratio: aspect_ratio_for(index),
          published: true
        )

      {:ok, _item} = Content.add_short_feed_video(scope, video)
    end

    viewer = insert(:subscribed_viewer, organization: org)
    session = log_in_viewer(session, viewer, org)

    %{session: session, org: org}
  end

  test "on a phone, scrolling to the next clip plays it, pauses the previous one and keeps at most three players",
       %{session: session, org: org} do
    {width, height} = @mobile

    session =
      session
      |> resize_window(width, height)
      |> open_feed(org, "ok")
      |> scroll_to_clip(1)
      |> wait_for_state(1, "playing")
      |> wait_for_state(0, "paused")

    assert player_count(session) <= 3
    assert play_calls(session, 1) >= 1

    # Clip 2 was playing under the stub; moving on must pause it.
    session =
      session
      |> scroll_to_clip(2)
      |> wait_for_state(2, "playing")
      |> wait_for_state(1, "paused")

    assert player_count(session) <= 3
  end

  test "on a desktop, ArrowDown/ArrowUp and j/k move between clips and focus the clip",
       %{session: session, org: org} do
    {width, height} = @desktop

    session =
      session
      |> resize_window(width, height)
      |> open_feed(org, "ok")
      |> focus_clip(0)

    session
    |> send_keys([:down_arrow])
    |> wait_for_focus(1)
    |> wait_for_state(1, "playing")
    |> send_keys(["j"])
    |> wait_for_focus(2)
    |> wait_for_state(2, "playing")
    |> wait_for_state(1, "paused")
    |> send_keys(["k"])
    |> wait_for_focus(1)
    |> wait_for_state(1, "playing")
    |> send_keys([:up_arrow])
    |> wait_for_focus(0)
    |> wait_for_state(0, "playing")

    assert player_count(session) <= 3
  end

  test "when autoplay is refused even muted, tap-to-play appears and starts the clip",
       %{session: session, org: org} do
    {width, height} = @mobile

    session =
      session
      |> resize_window(width, height)
      |> open_feed(org, "blocked")
      |> scroll_to_clip(1)
      |> assert_has(css("#shorts-feed[data-autoplay='blocked']"))
      |> assert_has(css("[data-test=shorts-tap-to-play]", visible: true))

    # The hook retried muted before giving up.
    assert play_calls(session, 1) >= 2

    session
    |> set_stub_mode("ok")
    |> click(css("[data-test=shorts-tap-to-play]"))
    |> wait_for_state(1, "playing")
    |> refute_has(css("#shorts-feed[data-autoplay='blocked']"))
  end

  test "backgrounding the tab pauses the active clip and it stays paused when the tab returns",
       %{session: session, org: org} do
    {width, height} = @mobile

    session =
      session
      |> resize_window(width, height)
      |> open_feed(org, "ok")
      |> scroll_to_clip(1)
      |> wait_for_state(1, "playing")
      |> set_visibility("hidden")
      |> wait_for_state(1, "paused")

    calls_while_hidden = play_calls(session, 1)

    # The visibilitychange listener runs synchronously inside the dispatch, so
    # any (wrong) resume has already happened when set_visibility returns.
    session = set_visibility(session, "visible")

    assert clip_state(session, 1) == "paused"
    assert play_calls(session, 1) == calls_while_hidden
  end

  test "scrolling near the end of the first page loads the next page, then shows the end of the feed",
       %{session: session, org: org} do
    {width, height} = @mobile

    session =
      session
      |> resize_window(width, height)
      |> open_feed(org, "ok")
      |> assert_has(css("#shorts-feed article", count: 8))
      |> refute_has(css("[data-test=shorts-end]"))
      |> scroll_to_clip(5)
      |> wait_for_state(5, "playing")
      |> assert_has(css("#shorts-feed article", count: @clip_count))
      |> assert_has(css("#shorts-feed[data-has-more='false']"))

    session
    |> scroll_to_clip(@clip_count - 1)
    |> wait_for_state(@clip_count - 1, "playing")
    |> assert_has(css("[data-test=shorts-end]"))

    assert player_count(session) <= 3
  end

  test "the Shorts nav item opens the feed and leaving through the nav removes every player",
       %{session: session, org: org} do
    {width, height} = @desktop

    session =
      session
      |> resize_window(width, height)
      |> visit("/?org=#{org.slug}")
      |> wait_for_live_view()
      |> stub_players("ok")
      |> click(css("[data-test=nav-shorts]"))
      |> assert_has(css("#shorts-feed article[data-index='0'] mux-player", visible: :any))
      |> wait_for_live_view()

    assert current_path(session) == "/shorts"
    assert player_count(session) >= 1

    session =
      session
      |> click(css("[data-test=nav-home]"))
      |> refute_has(css("#shorts-feed"))

    assert current_path(session) == "/"
    assert player_count(session) == 0
  end

  for {label, size} <- [mobile: @mobile, desktop: @desktop] do
    @size size
    test "on #{label}, portrait and landscape clips are fitted with contain, never stretched or cropped",
         %{session: session, org: org} do
      {width, height} = @size

      session =
        session
        |> resize_window(width, height)
        |> open_feed(org, "ok")
        |> wait_for_state(0, "playing")

      portrait = clip_geometry(session, 0)
      landscape = clip_geometry(session, 1)

      for {name, geometry, ratio} <- [
            {"9:16 clip", portrait, 9 / 16},
            {"16:9 clip", landscape, 16 / 9}
          ] do
        assert geometry["mediaBox"],
               "#{name}: no media box carrying an inline aspect-ratio inside the article"

        assert geometry["posterFit"] == "contain",
               "#{name}: poster object-fit is #{inspect(geometry["posterFit"])}"

        for fit <- geometry["playerFits"] do
          assert fit == "contain", "#{name}: player/video object-fit is #{inspect(fit)}"
        end

        assert geometry["boxHeight"] > 0, "#{name}: media box has no height"

        assert_within(
          geometry["boxWidth"] / geometry["boxHeight"],
          ratio,
          0.02,
          "#{name} media box ratio"
        )

        assert geometry["boxInsideArticle"],
               "#{name}: media box overflows its article: #{inspect(geometry)}"
      end

      # The portrait clip has a player (it is active); the stub never changes layout.
      assert portrait["playerFits"] != [], "the active 9:16 clip has no player to check"

      stage = portrait

      if width < 768 do
        # Phone: the stage is the full viewport width.
        assert_within(stage["articleWidth"], stage["viewportWidth"], 0.02, "mobile stage width")
      else
        # Desktop: the stage is a 9:16 column, not the full viewport.
        assert_within(
          stage["articleWidth"] / stage["articleHeight"],
          9 / 16,
          0.02,
          "desktop stage ratio"
        )

        assert stage["articleWidth"] < stage["viewportWidth"] * 0.6
      end
    end
  end

  # ---- helpers --------------------------------------------------------------

  # Viewers sign in through a magic link; the controller sets the viewer
  # session cookie and redirects to the org home.
  defp log_in_viewer(session, viewer, org) do
    {encoded_token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
    Repo.insert!(viewer_token)

    session
    |> visit("/magic-link/#{encoded_token}?org=#{org.slug}")
    |> assert_has(css("[data-test=sv-root]"))
  end

  # Stub first, then live-navigate, so no real player is ever created. The nav
  # item is hidden on phones, so it is clicked from script: LiveView handles
  # the click on the link the same way and performs a live navigation.
  defp open_feed(session, org, mode) do
    session
    |> visit("/?org=#{org.slug}")
    |> wait_for_live_view()
    |> stub_players(mode)
    |> click_nav_shorts()
    |> assert_has(css("#shorts-feed[role=feed]"))
    |> assert_has(css("#shorts-feed article[data-index='1']"))
    |> wait_for_live_view()
    |> assert_stub_survived()
  end

  defp click_nav_shorts(session) do
    eval(session, "document.querySelector('[data-test=\"nav-shorts\"]').click(); return true;")
    session
  end

  # A full page load would have discarded the stub; fail loudly if it did.
  defp assert_stub_survived(session) do
    assert eval(session, "return !!window.__shortsE2E;"),
           "the Shorts feed was reached by a full page load; the player stub is gone"

    session
  end

  # Hooks mount during the LiveView join, which finishes before the root
  # element is marked connected.
  defp wait_for_live_view(session) do
    assert_has(session, css("[data-phx-main].phx-connected"))
  end

  defp stub_players(session, mode) do
    eval(
      session,
      """
      window.__shortsE2E = { mode: arguments[0] };
      let Player = customElements.get('mux-player');
      if (!Player) {
        Player = class extends HTMLElement {};
        customElements.define('mux-player', Player);
      }
      // Network errors from a real player must not reach the hook's listener
      // on the element: capture at window runs first and stops the event.
      window.addEventListener('error', (event) => {
        if (event.target instanceof Player) event.stopImmediatePropagation();
      }, true);
      // Players created before the stub keep whatever state the real
      // element reported, so a later pause() is still observable.
      const existing = Array.from(document.querySelectorAll('mux-player'));
      const before = existing.map((el) => el.paused !== false);
      const proto = Player.prototype;
      Object.defineProperty(proto, 'paused', {
        configurable: true,
        get() { return this.__e2ePaused !== false; },
      });
      Object.defineProperty(proto, 'muted', {
        configurable: true,
        get() { return this.__e2eMuted === true || this.hasAttribute('muted'); },
        set(value) { this.__e2eMuted = !!value; },
      });
      proto.play = function () {
        const calls = Number(this.getAttribute('data-e2e-play-calls') || '0') + 1;
        this.setAttribute('data-e2e-play-calls', String(calls));
        if (window.__shortsE2E.mode === 'blocked') {
          return Promise.reject(new DOMException('autoplay refused', 'NotAllowedError'));
        }
        this.__e2ePaused = false;
        this.setAttribute('data-e2e-state', 'playing');
        this.dispatchEvent(new Event('play'));
        return Promise.resolve();
      };
      proto.pause = function () {
        const wasPlaying = this.__e2ePaused === false;
        this.__e2ePaused = true;
        this.setAttribute('data-e2e-state', 'paused');
        if (wasPlaying) this.dispatchEvent(new Event('pause'));
      };
      existing.forEach((el, i) => {
        el.__e2ePaused = before[i];
        el.setAttribute('data-e2e-state', before[i] ? 'paused' : 'playing');
      });
      return true;
      """,
      [mode]
    )

    session
  end

  defp set_stub_mode(session, mode) do
    eval(session, "window.__shortsE2E.mode = arguments[0]; return true;", [mode])
    session
  end

  defp scroll_to_clip(session, index) do
    eval(
      session,
      """
      const clip = document.querySelector('#shorts-feed article[data-index="' + arguments[0] + '"]');
      clip.scrollIntoView({block: 'start', behavior: 'auto'});
      return true;
      """,
      [index]
    )

    session
  end

  defp focus_clip(session, index) do
    eval(
      session,
      """
      const clip = document.querySelector('#shorts-feed article[data-index="' + arguments[0] + '"]');
      clip.focus();
      return document.activeElement === clip;
      """,
      [index]
    )

    session
  end

  defp set_visibility(session, state) do
    eval(
      session,
      """
      Object.defineProperty(document, 'visibilityState', {value: arguments[0], configurable: true});
      Object.defineProperty(document, 'hidden', {value: arguments[0] === 'hidden', configurable: true});
      document.dispatchEvent(new Event('visibilitychange'));
      return true;
      """,
      [state]
    )

    session
  end

  defp clip_state(session, index) do
    eval(
      session,
      """
      const clip = document.querySelector('#shorts-feed article[data-index="' + arguments[0] + '"]');
      const player = clip && clip.querySelector('mux-player');
      return player ? player.getAttribute('data-e2e-state') : null;
      """,
      [index]
    )
  end

  defp play_calls(session, index) do
    eval(
      session,
      """
      const clip = document.querySelector('#shorts-feed article[data-index="' + arguments[0] + '"]');
      const player = clip && clip.querySelector('mux-player');
      return player ? Number(player.getAttribute('data-e2e-play-calls') || '0') : 0;
      """,
      [index]
    )
  end

  defp player_count(session) do
    eval(session, "return document.querySelectorAll('mux-player').length;")
  end

  # Layout facts for one clip. The media box is the element inside the article
  # that carries the inline `aspect-ratio`; the poster is the article's <img>.
  defp clip_geometry(session, index) do
    eval(
      session,
      """
      const clip = document.querySelector('#shorts-feed article[data-index="' + arguments[0] + '"]');
      const box = clip.querySelector('[style*="aspect-ratio"]');
      const poster = clip.querySelector('img');
      const fitOf = (el) => {
        const style = getComputedStyle(el);
        const custom = style.getPropertyValue('--media-object-fit').trim();
        return style.objectFit === 'contain' || custom === 'contain' ? 'contain' : (custom || style.objectFit);
      };
      const players = Array.from(clip.querySelectorAll('mux-player, video'));
      const a = clip.getBoundingClientRect();
      const b = box ? box.getBoundingClientRect() : {left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 1};
      const slack = 1;
      return {
        mediaBox: !!box,
        posterFit: poster ? getComputedStyle(poster).objectFit : null,
        playerFits: players.map(fitOf),
        boxWidth: b.width,
        boxHeight: b.height,
        boxInsideArticle: !!box && b.width > 0 && b.left >= a.left - slack && b.right <= a.right + slack &&
          b.top >= a.top - slack && b.bottom <= a.bottom + slack,
        articleWidth: a.width,
        articleHeight: a.height,
        viewportWidth: window.innerWidth
      };
      """,
      [index]
    )
  end

  defp assert_within(actual, expected, tolerance, label) do
    assert abs(actual - expected) / expected <= tolerance,
           "#{label}: expected about #{expected}, got #{actual}"
  end

  defp wait_for_state(session, index, state) do
    eventually(session, "clip #{index} to be #{state}", fn ->
      clip_state(session, index) == state
    end)
  end

  defp wait_for_focus(session, index) do
    eventually(session, "clip #{index} to have focus", fn ->
      eval(
        session,
        """
        const active = document.activeElement;
        return !!active && active.tagName === 'ARTICLE' &&
          active.getAttribute('data-index') === String(arguments[0]);
        """,
        [index]
      )
    end)
  end

  # Polls the browser until `check` returns true, failing after `timeout_ms`.
  defp eventually(session, description, check, timeout_ms \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_eventually(session, description, check, deadline)
  end

  defp do_eventually(session, description, check, deadline) do
    cond do
      check.() ->
        session

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("timed out waiting for #{description}")

      true ->
        Process.sleep(50)
        do_eventually(session, description, check, deadline)
    end
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
end
