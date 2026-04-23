defmodule BobineWeb.Viewer.LiveEventPpvControllerTest do
  use BobineWeb.ConnCase, async: true

  import Mox

  setup :verify_on_exit!

  defp connected_org do
    insert(:organization,
      stripe_connect_account_id: "acct_test_ppv",
      stripe_connect_onboarding_complete: true
    )
  end

  defp ppv_event(org) do
    insert(:live_event,
      organization: org,
      access_type: "pay_per_view",
      ppv_price_cents: 999,
      title: "Big PPV Stream",
      slug: "big-ppv-stream"
    )
  end

  describe "POST /events/:slug/purchase" do
    test "redirects authenticated viewer to Stripe checkout URL", %{conn: conn} do
      org = connected_org()
      event = ppv_event(org)
      viewer = insert(:viewer, organization: org, email: "fan@example.com")

      expect(
        Bobine.Billing.MockStripeClient,
        :create_connected_payment_checkout_session,
        fn _params ->
          {:ok, %{url: "https://checkout.stripe.com/pay/cs_test_xyz"}}
        end
      )

      conn =
        conn_for_viewer(viewer)
        |> post("/events/#{event.slug}/purchase")

      assert redirected_to(conn) == "https://checkout.stripe.com/pay/cs_test_xyz"
    end

    test "redirects unauthenticated viewer to login with flash error", %{conn: conn} do
      org = connected_org()
      event = ppv_event(org)

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})
        |> post("/events/#{event.slug}/purchase")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "sign in"
    end

    test "returns 404 for a non-existent event", %{conn: conn} do
      org = connected_org()
      viewer = insert(:viewer, organization: org)

      conn =
        conn_for_viewer(viewer)
        |> post("/events/does-not-exist/purchase")

      assert conn.status == 404
    end

    test "returns 404 for a non-PPV event", %{conn: conn} do
      org = connected_org()
      sub_event = insert(:live_event, organization: org, access_type: "subscribers_only")
      viewer = insert(:viewer, organization: org)

      conn =
        conn_for_viewer(viewer)
        |> post("/events/#{sub_event.slug}/purchase")

      assert conn.status == 404
    end

    test "flashes error and redirects home when org Stripe not connected", %{conn: conn} do
      org = insert(:organization, stripe_connect_onboarding_complete: false)
      event = ppv_event(org)
      viewer = insert(:viewer, organization: org)

      conn =
        conn_for_viewer(viewer)
        |> post("/events/#{event.slug}/purchase")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not available"
      assert redirected_to(conn) == ~p"/"
    end

    test "flashes error and redirects home when Stripe returns an error", %{conn: conn} do
      org = connected_org()
      event = ppv_event(org)
      viewer = insert(:viewer, organization: org)

      expect(
        Bobine.Billing.MockStripeClient,
        :create_connected_payment_checkout_session,
        fn _params ->
          {:error, :stripe_error, %{message: "Something went wrong"}}
        end
      )

      conn =
        conn_for_viewer(viewer)
        |> post("/events/#{event.slug}/purchase")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "error"
      assert redirected_to(conn) == ~p"/"
    end
  end
end
