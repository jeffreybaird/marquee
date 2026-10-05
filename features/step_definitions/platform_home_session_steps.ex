defmodule MarqueeFeatures.Steps.PlatformHomeSession do
  @moduledoc "Browser acceptance for returning from a tenant to the platform root."
  use Cucumberex.DSL
  use Wallaby.DSL

  import Marquee.Factory
  import Wallaby.Query

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
