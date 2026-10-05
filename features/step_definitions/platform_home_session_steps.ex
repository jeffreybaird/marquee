defmodule MarqueeFeatures.Steps.PlatformHomeSession do
  @moduledoc "Browser acceptance for returning from a tenant to the platform root."
  use Cucumberex.DSL
  use Wallaby.DSL

  import ExUnit.Assertions
  import Marquee.Factory
  import Wallaby.Query

  when_("I open the platform homepage on desktop and mobile", fn world ->
    geometry =
      for width <- [1280, 390] do
        session =
          world.session
          |> resize_window(width, 900)
          |> visit("/")
          |> assert_has(
            css("[data-test=portfolio-disclosure]",
              text: "Marquee is a portfolio project, not a real business."
            )
          )

        execute_script(
          session,
          """
          const banner=document.querySelector('[data-test="portfolio-disclosure"]');
          const b=banner.getBoundingClientRect(), h=document.querySelector('[data-test="marketing-headline"]').getBoundingClientRect();
          return {top:b.top,bottom:b.bottom,left:b.left,width:b.width,viewport:innerWidth,height:innerHeight,heroTop:h.top,role:banner.getAttribute('role'),overflow:document.documentElement.scrollWidth>innerWidth};
          """,
          fn rect ->
            assert rect["role"] == "note"
            assert rect["top"] >= 0
            assert rect["bottom"] <= rect["height"]
            assert rect["bottom"] <= rect["heroTop"]
            assert rect["left"] <= 1
            assert rect["width"] >= rect["viewport"] - 2
            refute rect["overflow"]
          end
        )
      end

    Map.put(world, :portfolio_viewports_checked, length(geometry))
  end)

  then_("the portfolio disclosure is visible above the hero on both screens", fn world ->
    assert world.portfolio_viewports_checked == 2
    world
  end)

  given_("a tenant is available for a platform homepage return visit", fn world ->
    Map.put(world, :platform_return_org, insert(:organization))
  end)

  when_("I visit that tenant and then the bare platform homepage", fn world ->
    session =
      world.session
      |> visit("/?org=#{world.platform_return_org.slug}")
      |> assert_has(css("[data-test=org-landing]"))
      |> visit("/")

    Map.put(world, :session, session)
  end)

  then_("I see the platform marketing homepage", fn world ->
    assert_has(world.session, css("[data-test=platform-marketing]"))
    assert_has(world.session, css("[data-test=marketing-headline]"))
    world
  end)
end
