defmodule Marquee.DemoSeederTest do
  use Marquee.DataCase, async: false

  alias Marquee.DemoSeeder

  doctest Marquee.DemoSeeder, only: [org_slugs: 0]

  describe "org_slugs/0" do
    test "lists the five demo org slugs in order" do
      assert DemoSeeder.org_slugs() == [
               "wanderlust-tv",
               "the-workshop",
               "zenith-fitness",
               "art-of-war-40k",
               "prism-plus"
             ]
    end
  end

  describe "seed/1" do
    test "raises for an unknown org slug before any external call" do
      assert_raise RuntimeError, ~r/Unknown org slug: nope/, fn ->
        DemoSeeder.seed(pexels_key: "test-key", org: "nope")
      end
    end

    test "raises when no Pexels key is available" do
      original = System.get_env("PEXELS_API_KEY")
      System.delete_env("PEXELS_API_KEY")

      try do
        assert_raise RuntimeError, ~r/PEXELS_API_KEY/, fn ->
          DemoSeeder.seed(pexels_key: nil, org: "wanderlust-tv")
        end
      after
        if original, do: System.put_env("PEXELS_API_KEY", original)
      end
    end
  end
end
