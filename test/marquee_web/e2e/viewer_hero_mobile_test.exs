defmodule MarqueeWeb.E2E.ViewerHeroMobileTest do
  @moduledoc """
  Browser coverage for the hero carousel on a phone-sized viewport.

  LiveViewTest cannot exercise the HeroCarousel hook's touch handling or the
  responsive stylesheet, so this suite drives real Chrome: a signed-in viewer
  opens the org home at 390px, swipes the hero, and the arrow buttons must be
  hidden there while remaining available at desktop width.
  """
  use MarqueeWeb.WallabyCase

  alias Marquee.Repo
  alias Marquee.Viewers.ViewerToken

  @moduletag :e2e

  @mobile {390, 844}
  @desktop {1280, 900}

  setup %{session: session} do
    org = insert(:organization)
    viewer = insert(:viewer, organization: org)

    # Auto-advance off so the only thing that moves the active slide is the swipe.
    hero_row = insert(:hero_row, organization: org, filter_config: %{"auto_advance_ms" => 0})

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

    session = log_in_viewer(session, viewer, org)

    %{session: session, org: org, viewer: viewer}
  end

  test "mobile viewers swipe between hero slides and never see the arrow buttons",
       %{session: session, org: org} do
    {width, height} = @mobile

    session =
      session
      |> resize_window(width, height)
      |> visit("/?org=#{org.slug}")
      |> assert_has(css("[data-test=hero-carousel][data-auto-advance='0']"))
      |> assert_has(css("[data-test=hero-slide-0].active"))
      |> assert_has(css("[data-test=hero-pagination]", visible: true))
      |> refute_has(css("[data-test=hero-arrow-prev]", visible: true))
      |> refute_has(css("[data-test=hero-arrow-next]", visible: true))
      |> assert_has(css("[data-test=hero-arrow-prev]", visible: false))
      |> assert_has(css("[data-test=hero-arrow-next]", visible: false))
      |> wait_for_live_view()

    session
    |> swipe_hero(from_x: 300, to_x: 100)
    |> assert_has(css("[data-test=hero-slide-1].active"))
    |> assert_has(css("[data-test=hero-dot-1][aria-selected='true']"))
    |> assert_has(css("[data-test=hero-dot-0][aria-selected='false']"))
    |> refute_has(css("[data-test=hero-slide-0].active"))
  end

  test "swiping right goes back to the previous slide, wrapping from the first",
       %{session: session, org: org} do
    {width, height} = @mobile

    session
    |> resize_window(width, height)
    |> visit("/?org=#{org.slug}")
    |> assert_has(css("[data-test=hero-slide-0].active"))
    |> wait_for_live_view()
    |> swipe_hero(from_x: 100, to_x: 300)
    |> assert_has(css("[data-test=hero-slide-1].active"))
    |> assert_has(css("[data-test=hero-dot-1][aria-selected='true']"))
  end

  test "a short tap on the hero leaves the active slide alone", %{session: session, org: org} do
    {width, height} = @mobile

    session =
      session
      |> resize_window(width, height)
      |> visit("/?org=#{org.slug}")
      |> assert_has(css("[data-test=hero-slide-0].active"))
      |> wait_for_live_view()
      |> swipe_hero(from_x: 200, to_x: 180)

    assert active_slide_index(session) == 0
    assert_has(session, css("[data-test=hero-dot-0][aria-selected='true']"))
  end

  test "desktop viewers keep both arrow buttons", %{session: session, org: org} do
    {width, height} = @desktop

    session
    |> resize_window(width, height)
    |> visit("/?org=#{org.slug}")
    |> assert_has(css("[data-test=hero-carousel]"))
    |> assert_has(css("[data-test=hero-arrow-prev]", visible: true))
    |> assert_has(css("[data-test=hero-arrow-next]", visible: true))
    |> assert_has(css("[data-test=hero-pagination]", visible: true))
  end

  # ---- helpers --------------------------------------------------------------

  # Viewers sign in through a magic link; the controller sets the viewer
  # session cookie and redirects to the org home.
  defp log_in_viewer(session, viewer, org) do
    {encoded_token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
    Repo.insert!(viewer_token)

    session
    |> visit("/magic-link/#{encoded_token}?org=#{org.slug}")
    |> assert_has(css("[data-test=hero-carousel]"))
  end

  # Hooks mount during the LiveView join, which finishes before the root
  # element is marked connected. Dispatching the swipe before that point
  # would reach a carousel with no listeners attached.
  defp wait_for_live_view(session) do
    assert_has(session, css("[data-phx-main].phx-connected"))
  end

  # Real Chrome exposes the `Touch` constructor, so the hook sees the same
  # event shape a finger produces: one touch on touchstart, the lifted point
  # in `changedTouches` on touchend.
  defp swipe_hero(session, from_x: from_x, to_x: to_x) do
    execute_script(
      session,
      """
      const el = document.querySelector('[data-test="hero-carousel"]');
      const point = (x) => new Touch({identifier: 1, target: el, clientX: x, clientY: 300});
      const start = point(arguments[0]);
      const stop = point(arguments[1]);
      el.dispatchEvent(new TouchEvent('touchstart', {touches: [start], changedTouches: [start], bubbles: true, cancelable: true}));
      el.dispatchEvent(new TouchEvent('touchend', {touches: [], changedTouches: [stop], bubbles: true, cancelable: true}));
      return true;
      """,
      [from_x, to_x]
    )
  end

  defp active_slide_index(session) do
    execute_script(
      session,
      """
      const slides = Array.from(document.querySelectorAll('[data-test="hero-carousel"] .hero-slide'));
      return slides.findIndex((slide) => slide.classList.contains('active'));
      """,
      fn index -> send(self(), {:active_slide_index, index}) end
    )

    receive do
      {:active_slide_index, index} -> index
    after
      5_000 -> flunk("hero slide index was not reported by the browser")
    end
  end
end
