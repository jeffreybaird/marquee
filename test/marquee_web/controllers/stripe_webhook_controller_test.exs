defmodule MarqueeWeb.StripeWebhookControllerTest do
  use MarqueeWeb.ConnCase, async: true

  # In test env, :stripe_webhook_secret is nil by default, so the controller
  # falls through to the JSON decode path (no signature verification).
  # Oban is configured with `testing: :inline` so jobs execute immediately
  # inside Oban.insert — we assert HTTP status, not job enqueue.

  defp post_stripe(conn, payload, headers \\ []) do
    Process.put(:raw_body, payload)

    conn =
      Enum.reduce(headers, conn, fn {k, v}, acc ->
        put_req_header(acc, k, v)
      end)

    conn
    |> put_req_header("content-type", "application/json")
    |> post("/webhooks/stripe", payload)
  end

  # ── No signing secret (dev/test fallback to JSON decode) ───────────────

  describe "POST /webhooks/stripe — no signing secret" do
    test "accepts valid JSON and returns 200", %{conn: conn} do
      event = build_stripe_event("invoice.payment_succeeded", %{"subscription" => "sub_1"})

      conn = post_stripe(conn, Jason.encode!(event))
      assert conn.status == 200
    end

    test "rejects malformed JSON at the plug layer", %{conn: conn} do
      assert_raise Plug.Parsers.ParseError, fn ->
        post_stripe(conn, "not valid json {{{")
      end
    end

    test "returns 200 for platform event without Stripe-Account header", %{conn: conn} do
      event =
        build_stripe_event("customer.subscription.updated", %{
          "id" => "sub_plat",
          "status" => "active"
        })

      conn = post_stripe(conn, Jason.encode!(event))
      assert conn.status == 200
    end

    test "returns 200 for connected event with Stripe-Account header", %{conn: conn} do
      event =
        build_stripe_event("checkout.session.completed", %{
          "subscription" => "sub_c",
          "customer" => "cus_c",
          "customer_email" => "v@example.com"
        })

      conn = post_stripe(conn, Jason.encode!(event), [{"stripe-account", "acct_test_123"}])
      assert conn.status == 200
    end
  end

  # ── With signing secret ────────────────────────────────────────────────

  describe "POST /webhooks/stripe — with signing secret" do
    setup do
      Application.put_env(:marquee, :stripe_webhook_secret, "whsec_test_secret")

      on_exit(fn ->
        Application.delete_env(:marquee, :stripe_webhook_secret)
      end)

      :ok
    end

    test "returns 400 when no Stripe-Signature header present", %{conn: conn} do
      payload = Jason.encode!(build_stripe_event("invoice.paid", %{}))

      conn = post_stripe(conn, payload)
      assert conn.status == 400
    end

    test "returns 400 when Stripe-Signature is invalid", %{conn: conn} do
      payload = Jason.encode!(build_stripe_event("invoice.paid", %{}))

      conn = post_stripe(conn, payload, [{"stripe-signature", "t=123,v1=invalid_signature"}])
      assert conn.status == 400
    end
  end

  # ── Connect webhook secret ────────────────────────────────────────────

  describe "POST /webhooks/stripe — connect webhook secret" do
    setup do
      Application.put_env(:marquee, :stripe_connect_webhook_secret, "whsec_connect_secret")

      on_exit(fn ->
        Application.delete_env(:marquee, :stripe_connect_webhook_secret)
        Application.delete_env(:marquee, :stripe_webhook_secret)
      end)

      :ok
    end

    test "uses connect signing secret when Stripe-Account header present", %{conn: conn} do
      payload = Jason.encode!(build_stripe_event("checkout.session.completed", %{}))

      conn =
        post_stripe(conn, payload, [
          {"stripe-account", "acct_connected"},
          {"stripe-signature", "t=123,v1=bad"}
        ])

      assert conn.status == 400
    end

    test "falls back to platform secret for platform events", %{conn: conn} do
      # No platform secret set, no Stripe-Account header → falls to JSON decode path
      payload = Jason.encode!(build_stripe_event("invoice.paid", %{}))

      conn = post_stripe(conn, payload)
      # No platform webhook secret set, so falls through to JSON decode → 200
      assert conn.status == 200
    end
  end

  # ── All Stripe event types accepted (200) ──────────────────────────────
  # Verifies every event type the Stripe CLI sends during a checkout flow
  # is accepted by the webhook endpoint without error.

  describe "POST /webhooks/stripe — all event types return 200" do
    @platform_events [
      {"checkout.session.completed",
       %{
         "subscription" => "sub_1",
         "customer" => "cus_1",
         "metadata" => %{}
       }},
      {"customer.created", %{"id" => "cus_new", "email" => "t@example.com"}},
      {"customer.updated", %{"id" => "cus_upd", "email" => "t@example.com"}},
      {"customer.subscription.created",
       %{"id" => "sub_cr", "status" => "active", "customer" => "cus_1"}},
      {"customer.subscription.updated",
       %{"id" => "sub_upd", "status" => "active", "cancel_at_period_end" => false}},
      {"customer.subscription.deleted", %{"id" => "sub_del"}},
      {"charge.succeeded",
       %{"id" => "ch_1", "amount" => 999, "currency" => "usd", "status" => "succeeded"}},
      {"payment_intent.created",
       %{"id" => "pi_1", "amount" => 999, "status" => "requires_payment_method"}},
      {"payment_intent.succeeded", %{"id" => "pi_2", "amount" => 999, "status" => "succeeded"}},
      {"payment_method.attached", %{"id" => "pm_1", "type" => "card", "customer" => "cus_1"}},
      {"invoice.created", %{"id" => "in_1", "subscription" => "sub_1", "status" => "draft"}},
      {"invoice.finalized", %{"id" => "in_2", "subscription" => "sub_1", "status" => "open"}},
      {"invoice.updated", %{"id" => "in_3", "subscription" => "sub_1", "status" => "open"}},
      {"invoice.paid", %{"id" => "in_4", "subscription" => "sub_1", "status" => "paid"}},
      {"invoice.payment_succeeded", %{"id" => "in_5", "subscription" => "sub_1"}},
      {"invoice.payment_failed", %{"id" => "in_6", "subscription" => "sub_1"}},
      {"invoice_payment.paid", %{"id" => "inpay_1", "invoice" => "in_1", "status" => "paid"}},
      {"charge.updated", %{"id" => "ch_2", "amount" => 999}},
      {"setup_intent.created", %{"id" => "seti_1", "status" => "requires_payment_method"}},
      {"mandate.updated", %{"id" => "mandate_1", "status" => "active"}}
    ]

    for {event_type, object} <- @platform_events do
      @event_type event_type
      @object object

      test "platform #{event_type} returns 200", %{conn: conn} do
        event = build_stripe_event(@event_type, @object)
        conn = post_stripe(conn, Jason.encode!(event))

        assert conn.status == 200,
               "Expected 200 for platform #{@event_type}, got #{conn.status}"
      end
    end

    @connected_events [
      {"checkout.session.completed",
       %{
         "subscription" => "sub_c1",
         "customer" => "cus_c1",
         "customer_email" => "v@example.com"
       }},
      {"customer.subscription.updated",
       %{
         "id" => "sub_c_upd",
         "status" => "active",
         "cancel_at_period_end" => true,
         "current_period_start" => 1_700_000_000,
         "current_period_end" => 1_702_000_000
       }},
      {"customer.subscription.deleted", %{"id" => "sub_c_del"}},
      {"customer.subscription.trial_will_end",
       %{"id" => "sub_trial", "trial_end" => 1_700_000_000}},
      {"invoice.payment_succeeded", %{"id" => "in_c5", "subscription" => "sub_c1"}},
      {"invoice.payment_failed", %{"id" => "in_c6", "subscription" => "sub_c1"}},
      {"charge.succeeded", %{"id" => "ch_c1", "amount" => 999, "status" => "succeeded"}},
      {"customer.created", %{"id" => "cus_c_new", "email" => "c@example.com"}},
      {"customer.updated", %{"id" => "cus_c_upd"}},
      {"customer.subscription.created",
       %{"id" => "sub_c_cr", "status" => "active", "customer" => "cus_c1"}},
      {"payment_intent.created", %{"id" => "pi_c1", "amount" => 999}},
      {"payment_intent.succeeded", %{"id" => "pi_c2", "amount" => 999, "status" => "succeeded"}},
      {"payment_method.attached", %{"id" => "pm_c1", "type" => "card", "customer" => "cus_c1"}},
      {"invoice.created", %{"id" => "in_c1", "subscription" => "sub_c1", "status" => "draft"}},
      {"invoice.finalized", %{"id" => "in_c2", "subscription" => "sub_c1", "status" => "open"}},
      {"invoice.updated", %{"id" => "in_c3", "subscription" => "sub_c1", "status" => "open"}},
      {"invoice.paid", %{"id" => "in_c4", "subscription" => "sub_c1", "status" => "paid"}},
      {"invoice_payment.paid", %{"id" => "inpay_c1", "invoice" => "in_c1", "status" => "paid"}}
    ]

    for {event_type, object} <- @connected_events do
      @event_type event_type
      @object object

      test "connected #{event_type} returns 200", %{conn: conn} do
        event = build_stripe_event(@event_type, @object)

        conn =
          post_stripe(conn, Jason.encode!(event), [{"stripe-account", "acct_connected_test"}])

        assert conn.status == 200,
               "Expected 200 for connected #{@event_type}, got #{conn.status}"
      end
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp build_stripe_event(type, object) do
    %{
      "id" => "evt_test_#{System.unique_integer([:positive])}",
      "type" => type,
      "object" => "event",
      "data" => %{"object" => object}
    }
  end
end
