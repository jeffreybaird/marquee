defmodule Marquee.ReleaseTest do
  use Marquee.DataCase, async: false

  describe "seed_demo/1" do
    test "boots the app and delegates to DemoSeeder" do
      # An unknown slug makes DemoSeeder.seed/1 raise before any Pexels/Mux
      # call, so this proves seed_demo/1 starts the app and forwards its opts
      # without hitting an external service.
      assert_raise RuntimeError, ~r/Unknown org slug: nope/, fn ->
        Marquee.Release.seed_demo(pexels_key: "test-key", org: "nope")
      end
    end
  end
end
