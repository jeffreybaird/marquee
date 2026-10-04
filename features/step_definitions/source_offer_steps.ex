defmodule MarqueeFeatures.Steps.SourceOffer do
  @moduledoc "Step definitions for the public source and license offer."

  use Cucumberex.DSL
  use Wallaby.DSL
  import Wallaby.Query

  given_("I visit the public sign-in page for the source offer", fn world ->
    Map.put(world, :session, visit(world.session, "/users/log-in"))
  end)

  then_("the public Marquee source and license links are visible", fn world ->
    assert_has(
      world.session,
      css("a[data-test=source-code][href='https://github.com/jeffreybaird/marquee']",
        text: "Source code"
      )
    )

    assert_has(
      world.session,
      css(
        "a[data-test=license][href='https://github.com/jeffreybaird/marquee/blob/main/LICENSE']",
        text: "AGPL-3.0"
      )
    )

    world
  end)
end
