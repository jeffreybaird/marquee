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

  describe "reconcile_mux/1" do
    test "boots the app and delegates to Content, returning a summary" do
      # No pending Mux assets in this sandbox, so no external call is made and
      # the summary is all zeros — proving reconcile_mux/1 boots the app and
      # forwards to Content.reconcile_pending_mux_assets/1.
      assert %{ready: 0, errored: 0, still_pending: 0, failed: 0} =
               Marquee.Release.reconcile_mux()
    end
  end
end
