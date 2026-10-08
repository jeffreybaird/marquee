defmodule MarqueeFeatures.Steps.HeroCarousel do
  @moduledoc """
  Step definitions for hero_carousel.feature.

  Browser-driven: a viewer signs in through their magic link, the window is
  shrunk to a phone, and a synthetic touch swipe is dispatched on the hero
  carousel so the HeroCarousel hook and the responsive stylesheet are both
  exercised in real Chrome.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Marquee.Factory

  alias Marquee.Repo
  alias Marquee.Viewers.ViewerToken

  # ---- Setup --------------------------------------------------------------

  given_ "an organization has multiple hero slides", fn world ->
    org = insert(:organization)

    # Auto-advance is switched off so only the viewer's swipe moves the slide.
    hero_row = insert(:hero_row, organization: org, filter_config: %{"auto_advance_ms" => 0})

    slides =
      for index <- 0..1 do
        video =
          insert(:video,
            organization: org,
            title: "Hero video #{index}",
            mux_status: "ready",
            published: true
          )

        insert(:hero_slide,
          organization: org,
          row: hero_row,
          video: video,
          position: index,
          headline: "Hero slide #{index}",
          background_image_url: "/images/logo.svg"
        )
      end

    Map.merge(world, %{org: org, hero_row: hero_row, hero_slides: slides})
  end

  # ---- Viewer actions -----------------------------------------------------

  # A viewer of the org signs in through their magic link, then the window
  # shrinks to a phone before the homepage is loaded.
  when_ "I open the homepage as a viewer on a mobile screen", fn world ->
    viewer = insert(:viewer, organization: world.org)
    {encoded_token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
    Repo.insert!(viewer_token)

    session =
      world.session
      |> visit("/magic-link/#{encoded_token}?org=#{world.org.slug}")
      |> assert_has(css("[data-test=hero-carousel]"))
      |> resize_window(390, 844)
      |> visit("/?org=#{world.org.slug}")
      |> assert_has(css("[data-test=hero-carousel][data-auto-advance='0']"))
      |> assert_has(css("[data-test=hero-slide-0].active"))
      # Hooks mount during the LiveView join, before the root is marked
      # connected; a swipe dispatched earlier would find no listeners.
      |> assert_has(css("[data-phx-main].phx-connected"))

    Map.merge(world, %{session: session, viewer: viewer})
  end

  # Real Chrome exposes the `Touch` constructor, so the hook sees the same
  # event shape a finger produces: one touch on touchstart, the lifted point
  # in `changedTouches` on touchend.
  when_ "I swipe left on the hero banner", fn world ->
    session =
      execute_script(
        world.session,
        """
        const el = document.querySelector('[data-test="hero-carousel"]');
        const point = (x) => new Touch({identifier: 1, target: el, clientX: x, clientY: 300});
        const start = point(300);
        const stop = point(100);
        el.dispatchEvent(new TouchEvent('touchstart', {touches: [start], changedTouches: [start], bubbles: true, cancelable: true}));
        el.dispatchEvent(new TouchEvent('touchend', {touches: [], changedTouches: [stop], bubbles: true, cancelable: true}));
        return true;
        """
      )

    Map.put(world, :session, session)
  end

  # ---- Assertions ---------------------------------------------------------

  then_ "the next hero slide is shown", fn world ->
    world.session
    |> assert_has(css("[data-test=hero-slide-1].active"))
    |> assert_has(css("[data-test=hero-dot-1][aria-selected='true']"))
    |> assert_has(css("[data-test=hero-dot-0][aria-selected='false']"))
    |> refute_has(css("[data-test=hero-slide-0].active"))

    world
  end

  then_ "the hero arrow buttons are hidden", fn world ->
    world.session
    |> assert_has(css("[data-test=hero-pagination]", visible: true))
    |> refute_has(css("[data-test=hero-arrow-prev]", visible: true))
    |> refute_has(css("[data-test=hero-arrow-next]", visible: true))
    |> assert_has(css("[data-test=hero-arrow-prev]", visible: false))
    |> assert_has(css("[data-test=hero-arrow-next]", visible: false))

    world
  end
end
