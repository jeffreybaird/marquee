defmodule MarqueeFeatures.Steps.ShortsPlaybackRecovery do
  use Cucumberex.DSL
  import ExUnit.Assertions
  import Wallaby.Browser
  import Wallaby.Query
  import MarqueeFeatures.Support.Browser
  alias Marquee.Accounts.Scope
  alias Marquee.Content
  alias Marquee.Factory
  alias Marquee.Repo
  alias Marquee.Viewers.ViewerToken

  when_("a Short resumes playback after a source failure", fn world ->
    org = Factory.insert(:organization, shorts_feed_enabled: true, shorts_feed_access: "public")

    membership =
      Factory.insert(:membership, organization: org, role: :owner) |> Repo.preload(:user)

    scope = Scope.for_user(membership.user) |> Scope.with_organization(org, membership)

    for _n <- 1..2 do
      video =
        Factory.insert(:video,
          organization: org,
          published: true,
          mux_status: "ready",
          aspect_ratio: "9:16",
          duration: 20.0
        )

      assert {:ok, _} = Content.add_short_feed_video(scope, video)
    end

    assert {:ok, %{results: seeded}} = Content.list_short_feed(org)
    assert length(seeded) == 2
    viewer = Factory.insert(:subscribed_viewer, organization: org)
    {token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
    Repo.insert!(viewer_token)

    session =
      world.session
      |> visit("/magic-link/#{token}?org=#{org.slug}")
      |> assert_has(css("[data-test=sv-root]"))

    session = session |> visit_live("/?org=#{org.slug}")

    session =
      execute_script(session, """
      window.__shortsRecoveryFatal = true;
      let Player = customElements.get('mux-player');
      if (!Player) { Player = class extends HTMLElement {}; customElements.define('mux-player', Player); }
      window.addEventListener('error', event => {
        if (event.target instanceof Player) event.stopImmediatePropagation();
      }, true);
      Object.defineProperty(Player.prototype, 'paused', {configurable: true, get() { return this.__paused !== false; }});
      Player.prototype.pause = function() { this.__paused = true; this.dispatchEvent(new Event('pause')); };
      Player.prototype.play = function() {
        if (window.__shortsRecoveryFatal) return Promise.reject(new DOMException('bad source', 'NotSupportedError'));
        this.__paused = false; this.setAttribute('data-recovery-playing', 'true');
        this.dispatchEvent(new Event('play')); this.dispatchEvent(new Event('playing'));
        return Promise.resolve();
      };
      document.querySelector('[data-test=nav-shorts]').click();
      return true;
      """)

    session =
      session
      |> assert_has(css("#shorts-feed[role=feed]"))
      |> await_live_connect()
      |> assert_has(css("#shorts-feed article[data-index='1']", visible: :any))

    session =
      execute_script(
        session,
        "document.querySelector('#shorts-feed article[data-index=\"1\"]').scrollIntoView({block:'start',behavior:'auto'}); return true;"
      )

    session =
      session
      |> assert_has(
        css("#shorts-feed article[data-index='1'][data-state=error] [data-shorts-retry]",
          visible: true
        )
      )

    session =
      execute_script(
        session,
        "window.__shortsRecoveryFatal = false; document.querySelector('#shorts-feed article[data-index=\"1\"] mux-player').play(); return true;"
      )

    Map.put(world, :session, session)
  end)

  then_("the playing Short has no visible Retry overlay", fn world ->
    assert_has(
      world.session,
      css("#shorts-feed article[data-index='1'] mux-player[data-recovery-playing=true]",
        visible: :any
      )
    )

    assert_has(
      world.session,
      css("#shorts-feed article[data-index='1']:not([data-state=error]) [role=alert][hidden]",
        visible: :any
      )
    )

    refute_has(
      world.session,
      css("#shorts-feed article[data-index='1'] [data-shorts-retry]", visible: true)
    )

    world
  end)
end
