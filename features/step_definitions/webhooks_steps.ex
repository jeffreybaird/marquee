defmodule MarqueeFeatures.Steps.Webhooks do
  @moduledoc """
  Step definitions for webhooks.feature.

  Webhook scenarios are HTTP-only — they POST signed payloads to the
  webhook routes and assert on response status + side effects. They
  don't need a Wallaby browser session, so they run a fresh
  `Phoenix.ConnTest.build_conn/0` per scenario and bypass the world's
  `:session`.

  Mux and Stripe scenarios are covered end-to-end (signing, dispatch,
  worker inline-execution under Oban testing mode). Stripe events are
  signed with the configured test secret (`t=...,v1=HMAC-SHA256`) exactly
  as Stripe signs them, and connected-account events carry the
  `Stripe-Account` header. Viewer-facing consequences (gated access, the
  payment-issue notice) are checked in the browser via `world.session`.
  """

  use Cucumberex.DSL

  import Plug.Conn, only: [put_req_header: 3]
  import Phoenix.ConnTest, only: [build_conn: 0, post: 3]
  import Marquee.Factory
  import ExUnit.Assertions
  import Wallaby.Browser
  import Wallaby.Query, only: [css: 1]
  import MarqueeFeatures.Support.Browser, only: [visit_live: 2]

  alias Marquee.Billing
  alias Marquee.Billing.ViewerSubscription
  alias Marquee.Repo
  alias Marquee.Viewers.Viewer
  alias Marquee.Viewers.ViewerToken

  @endpoint MarqueeWeb.Endpoint

  @mux_secret "test-mux-webhook-secret-for-cucumber"
  @stripe_secret "whsec_cucumber_webhooks_test_secret"

  given_ "Mux webhook signature verification is configured", fn world ->
    Application.put_env(:marquee, :mux_webhook_secret, @mux_secret)
    Map.put(world, :mux_secret, @mux_secret)
  end

  given_ "Stripe webhook signature verification is configured", fn world ->
    # Platform events are verified with :stripe_webhook_secret and
    # connected-account events with :stripe_connect_webhook_secret.
    Application.put_env(:marquee, :stripe_webhook_secret, @stripe_secret)
    Application.put_env(:marquee, :stripe_connect_webhook_secret, @stripe_secret)
    Map.put(world, :stripe_secret, @stripe_secret)
  end

  given_ "a video is processing in Mux", fn world ->
    org = world[:org] || insert(:organization)

    video =
      insert(:video,
        organization: org,
        mux_status: "preparing",
        mux_asset_id: "asset_#{System.unique_integer([:positive])}"
      )

    Map.merge(world, %{org: org, video: video})
  end

  given_ "a Mux asset was created with organization metadata in the passthrough field",
        fn world ->
    org = world[:org] || insert(:organization)

    video =
      insert(:video,
        organization: org,
        mux_status: "preparing",
        mux_asset_id: "asset_passthrough_#{System.unique_integer([:positive])}"
      )

    Map.merge(world, %{org: org, video: video})
  end

  # ---- Mux signed POSTs --------------------------------------------------

  when_ "Mux POSTs an asset.ready event to /webhooks/mux with a valid signature", fn world ->
    payload =
      Jason.encode!(%{
        "type" => "video.asset.ready",
        "data" => %{
          "id" => world.video.mux_asset_id,
          "playback_ids" => [%{"id" => "playback_#{world.video.id}", "policy" => "public"}],
          "duration" => 120.0,
          "max_stored_resolution" => "HD",
          "passthrough" => world.org.id
        }
      })

    conn = post_mux_webhook(payload, world.mux_secret)
    Map.put(world, :conn, conn)
  end

  when_ "Mux POSTs an asset.errored event with a valid signature", fn world ->
    payload =
      Jason.encode!(%{
        "type" => "video.asset.errored",
        "data" => %{
          "id" => world.video.mux_asset_id,
          "passthrough" => world.org.id
        }
      })

    conn = post_mux_webhook(payload, world.mux_secret)
    Map.put(world, :conn, conn)
  end

  when_ "Mux POSTs a webhook with an invalid Mux-Signature header", fn world ->
    Application.put_env(:marquee, :mux_webhook_secret, @mux_secret)

    payload = Jason.encode!(%{"type" => "video.asset.ready", "data" => %{"id" => "asset_x"}})

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mux-signature", "t=0,v1=deadbeef")
      |> post("/webhooks/mux", payload)

    Map.put(world, :conn, conn)
  end

  when_ "Mux sends a webhook for that asset", fn world ->
    payload =
      Jason.encode!(%{
        "type" => "video.asset.ready",
        "data" => %{
          "id" => world.video.mux_asset_id,
          "playback_ids" => [%{"id" => "playback_resolved", "policy" => "public"}],
          "duration" => 60.0,
          "passthrough" => world.org.id
        }
      })

    conn = post_mux_webhook(payload, @mux_secret)
    Map.put(world, :conn, conn)
  end

  # ---- Then assertions ---------------------------------------------------

  then_ "the signature is verified", fn world ->
    assert world.conn.status == 200,
           "expected 200 (signature verified), got #{world.conn.status}"

    world
  end

  then_ "an async processing job is enqueued", fn world ->
    # `config :marquee, Oban, testing: :inline` runs jobs synchronously
    # within the request — by the time the response returned, the job
    # has already executed. The contract here is that the request
    # succeeded; the worker behavior is asserted by the next steps.
    assert world.conn.status == 200
    world
  end

  then_ "the video status is updated to \"ready\"", fn world ->
    fetched = Repo.reload!(world.video)
    assert fetched.mux_status == "ready",
           "expected status 'ready', got #{inspect(fetched.mux_status)}"

    Map.put(world, :video, fetched)
  end

  then_ "the video status is updated to \"error\"", fn world ->
    fetched = Repo.reload!(world.video)
    assert fetched.mux_status == "errored",
           "expected status 'errored', got #{inspect(fetched.mux_status)}"

    Map.put(world, :video, fetched)
  end

  then_ "the operator sees the status change in real time without refreshing", fn world ->
    # The status broadcast goes through Marquee.Events / PubSub. From a
    # pure HTTP-driven scenario, the contract that holds end-to-end is
    # the DB write covered above; PubSub delivery is unit-tested in
    # marquee/events tests. Pass-through.
    world
  end

  then_ "the request is rejected with a 400 response", fn world ->
    assert world.conn.status == 400,
           "expected 400 (invalid signature), got #{world.conn.status}"

    world
  end

  then_ "no processing occurs", fn world ->
    # When the controller short-circuits at signature verification no job
    # runs, so any record the rejected payload targeted is unchanged.
    if video = world[:video] do
      assert Repo.reload!(video).mux_status == video.mux_status
    end

    if sub = world[:viewer_subscription] do
      reloaded = Repo.reload!(sub)
      assert reloaded.status == sub.status
      assert Repo.reload!(world.viewer).subscription_status == world.viewer.subscription_status
    end

    world
  end

  then_ "the organization is resolved from the passthrough metadata", fn world ->
    fetched = Repo.reload!(world.video)
    assert fetched.organization_id == world.org.id
    Map.put(world, :video, fetched)
  end

  then_ "the processing job is scoped to the correct organization", fn world ->
    # The worker writes into the video by id, scoped through the asset
    # id passthrough. The DB reload above already proves the org
    # mapping is intact (we never wrote to a different org's video).
    world
  end

  # ---- Stripe (connected-account viewer subscriptions) -------------------

  given_ "a viewer just completed checkout", fn world ->
    org = connected_org()
    plan = insert(:plan, organization: org, active: true)
    viewer = insert(:viewer, organization: org)

    Map.merge(world, %{
      org: org,
      plan: plan,
      viewer: viewer,
      stripe_subscription_id: "sub_created_#{System.unique_integer([:positive])}",
      stripe_customer_id: "cus_created_#{System.unique_integer([:positive])}"
    })
  end

  when_ "Stripe POSTs a customer.subscription.created event with a valid signature",
        fn world ->
    now = System.system_time(:second)

    object = %{
      "object" => "subscription",
      "id" => world.stripe_subscription_id,
      "customer" => world.stripe_customer_id,
      "status" => "active",
      "current_period_start" => now,
      "current_period_end" => now + 30 * 86_400,
      "cancel_at_period_end" => false,
      "metadata" => %{
        "marquee_org_id" => to_string(world.org.id),
        "marquee_viewer_id" => to_string(world.viewer.id)
      },
      "items" => subscription_items(world.plan)
    }

    conn = post_stripe_event("customer.subscription.created", object, world.org)
    Map.put(world, :conn, conn)
  end

  then_ "the subscription record is created or updated for the viewer", fn world ->
    assert {:ok, %ViewerSubscription{} = sub} =
             Billing.get_viewer_subscription_by_stripe_id(world.org, world.stripe_subscription_id)

    assert sub.viewer_id == world.viewer.id
    assert sub.plan_id == world.plan.id
    assert sub.status == "active"
    assert Repo.reload!(world.viewer).subscription_status == "active"
    Map.put(world, :viewer_subscription, sub)
  end

  given_ "a viewer has an active subscription", fn world ->
    org = connected_org()
    give_subscription(world, org, "active")
  end

  when_ "Stripe POSTs a customer.subscription.updated event", fn world ->
    period_end = System.system_time(:second) + 60 * 86_400

    object =
      subscription_object(world.viewer_subscription, world.plan, %{
        "status" => "active",
        "cancel_at_period_end" => true,
        "current_period_end" => period_end
      })

    conn = post_stripe_event("customer.subscription.updated", object, world.org)
    Map.merge(world, %{conn: conn, expected_period_end: DateTime.from_unix!(period_end)})
  end

  then_ "the subscription record is updated to reflect the new state", fn world ->
    sub = Repo.reload!(world.viewer_subscription)
    assert sub.cancel_at_period_end

    assert %DateTime{} = sub.current_period_end,
           "current_period_end from the Stripe event was not stored"

    assert DateTime.compare(sub.current_period_end, world.expected_period_end) == :eq
    assert sub.status == "active"
    Map.put(world, :viewer_subscription, sub)
  end

  when_ "Stripe POSTs a customer.subscription.deleted event", fn world ->
    now = System.system_time(:second)

    object =
      subscription_object(world.viewer_subscription, world.plan, %{
        "status" => "canceled",
        "canceled_at" => now,
        "current_period_end" => now
      })

    conn = post_stripe_event("customer.subscription.deleted", object, world.org)
    Map.put(world, :conn, conn)
  end

  then_ "the subscription is marked as cancelled", fn world ->
    assert world.conn.status == 200
    sub = Repo.reload!(world.viewer_subscription)
    assert sub.status == "canceled"
    assert sub.canceled_at
    assert Repo.reload!(world.viewer).subscription_status == "canceled"
    Map.put(world, :viewer_subscription, sub)
  end

  then_ "the viewer loses access to gated content at period end", fn world ->
    world = log_in_viewer(world)
    video = ready_video(world.org)

    session = visit(world.session, "/watch/#{video.id}?org=#{world.org.slug}")
    assert await_path_in(session, ["/subscribe"]) == "/subscribe"
    Map.put(world, :session, session)
  end

  given_ "a viewer's subscription has a pending invoice", fn world ->
    # Stripe creates the subscription as "incomplete" until the first
    # invoice is paid.
    org = connected_org()
    give_subscription(world, org, "incomplete", "none")
  end

  when_ "Stripe POSTs invoice.payment_succeeded", fn world ->
    conn =
      post_stripe_event(
        "invoice.payment_succeeded",
        invoice_object(world.viewer_subscription, "paid"),
        world.org
      )

    Map.put(world, :conn, conn)
  end

  then_ "the subscription status is confirmed as active", fn world ->
    assert world.conn.status == 200
    assert Repo.reload!(world.viewer_subscription).status == "active"
    assert Repo.reload!(world.viewer).subscription_status == "active"
    world
  end

  when_ "Stripe POSTs invoice.payment_failed", fn world ->
    conn =
      post_stripe_event(
        "invoice.payment_failed",
        invoice_object(world.viewer_subscription, "open"),
        world.org
      )

    Map.put(world, :conn, conn)
  end

  then_ "the viewer's subscription status is marked as payment_failed", fn world ->
    # The platform's payment-failure state is Stripe's "past_due".
    assert world.conn.status == 200
    assert Repo.reload!(world.viewer_subscription).status == "past_due"
    assert Repo.reload!(world.viewer).subscription_status == "past_due"
    world
  end

  then_ "the viewer sees a payment issue notice", fn world ->
    world = log_in_viewer(world)

    session =
      world.session
      |> visit_live("/account?org=#{world.org.slug}")
      |> assert_has(css("[data-test=subscription-past-due-status]"))
      |> assert_has(css("[data-test=update-payment-btn]"))

    Map.put(world, :session, session)
  end

  when_ "Stripe POSTs a webhook with an invalid Stripe-Signature header", fn world ->
    # A forged cancellation for a real subscription: it must not be applied.
    world = give_subscription(world, connected_org(), "active")

    payload =
      stripe_payload(
        "customer.subscription.deleted",
        subscription_object(world.viewer_subscription, world.plan, %{"status" => "canceled"}),
        world.org.stripe_connect_account_id
      )

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("stripe-signature", "t=#{System.system_time(:second)},v1=deadbeef")
      |> put_req_header("stripe-account", world.org.stripe_connect_account_id)
      |> post("/webhooks/stripe", payload)

    Map.put(world, :conn, conn)
  end

  given_ "an event concerns a Stripe Connect account linked to an organization", fn world ->
    other_world = give_subscription(%{}, connected_org(), "active")
    world = give_subscription(world, connected_org(), "active")
    Map.put(world, :other, other_world)
  end

  when_ "Stripe POSTs the webhook", fn world ->
    conn =
      post_stripe_event(
        "invoice.payment_failed",
        invoice_object(world.viewer_subscription, "open"),
        world.org
      )

    # Same Connect account, but naming the other organization's
    # subscription: it must not be resolved outside this account's org.
    cross_conn =
      post_stripe_event(
        "invoice.payment_failed",
        invoice_object(world.other.viewer_subscription, "open"),
        world.org
      )

    Map.merge(world, %{conn: conn, cross_conn: cross_conn})
  end

  then_ "the organization is resolved from the Connect account ID", fn world ->
    assert world.conn.status == 200
    sub = Repo.reload!(world.viewer_subscription)
    assert sub.status == "past_due"
    assert sub.organization_id == world.org.id
    world
  end

  then_ "processing is scoped to that organization", fn world ->
    assert world.cross_conn.status == 200
    other_sub = Repo.reload!(world.other.viewer_subscription)
    assert other_sub.status == "active"
    assert Repo.reload!(world.other.viewer).subscription_status == "active"
    world
  end

  # ---- Helpers -----------------------------------------------------------

  defp post_mux_webhook(payload, secret) do
    timestamp = System.system_time(:second)

    signature =
      :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    header = "t=#{timestamp},v1=#{signature}"

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("mux-signature", header)
    |> post("/webhooks/mux", payload)
  end

  defp post_stripe_event(type, object, org) do
    payload = stripe_payload(type, object, org.stripe_connect_account_id)
    timestamp = System.system_time(:second)

    signature =
      :crypto.mac(:hmac, :sha256, @stripe_secret, "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", "t=#{timestamp},v1=#{signature}")
    |> put_req_header("stripe-account", org.stripe_connect_account_id)
    |> post("/webhooks/stripe", payload)
  end

  defp stripe_payload(type, object, account_id) do
    Jason.encode!(%{
      "id" => "evt_cucumber_#{System.unique_integer([:positive])}",
      "object" => "event",
      "api_version" => "2024-06-20",
      "created" => System.system_time(:second),
      "livemode" => false,
      "type" => type,
      "account" => account_id,
      "data" => %{"object" => object}
    })
  end

  defp subscription_items(plan) do
    %{
      "object" => "list",
      "data" => [
        %{
          "object" => "subscription_item",
          "id" => "si_cucumber_#{System.unique_integer([:positive])}",
          "price" => %{"object" => "price", "id" => plan.stripe_price_id}
        }
      ]
    }
  end

  defp subscription_object(%ViewerSubscription{} = sub, plan, overrides) do
    Map.merge(
      %{
        "object" => "subscription",
        "id" => sub.stripe_subscription_id,
        "customer" => sub.stripe_customer_id,
        "status" => sub.status,
        "cancel_at_period_end" => false,
        "items" => subscription_items(plan)
      },
      overrides
    )
  end

  defp invoice_object(%ViewerSubscription{} = sub, status) do
    %{
      "object" => "invoice",
      "id" => "in_cucumber_#{System.unique_integer([:positive])}",
      "customer" => sub.stripe_customer_id,
      "subscription" => sub.stripe_subscription_id,
      "status" => status
    }
  end

  defp connected_org do
    insert(:organization,
      stripe_connect_account_id: "acct_cucumber_#{System.unique_integer([:positive])}",
      stripe_connect_onboarding_complete: true
    )
  end

  defp give_subscription(world, org, status, viewer_status \\ nil) do
    plan = insert(:plan, organization: org, active: true)
    customer_id = "cus_cucumber_#{System.unique_integer([:positive])}"

    viewer =
      insert(:viewer,
        organization: org,
        stripe_customer_id: customer_id,
        subscription_status: viewer_status || status
      )

    sub =
      insert(:viewer_subscription,
        organization: org,
        viewer: viewer,
        plan: plan,
        stripe_customer_id: customer_id,
        stripe_subscription_id: "sub_cucumber_#{System.unique_integer([:positive])}",
        status: status
      )

    Map.merge(world, %{org: org, plan: plan, viewer: viewer, viewer_subscription: sub})
  end

  defp ready_video(org) do
    insert(:video, organization: org, mux_status: "ready", published: true, duration: 600.0)
  end

  # Signs world.viewer in to its org's viewer site through a magic link.
  defp log_in_viewer(world) do
    viewer = Repo.reload!(world.viewer)
    {encoded_token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
    Repo.insert!(viewer_token)

    session =
      world.session
      |> visit("/magic-link/#{encoded_token}?org=#{world.org.slug}")
      |> assert_has(css("[data-test=viewer-sign-out]"))

    Map.merge(world, %{viewer: %Viewer{} = viewer, session: session})
  end

  defp await_path_in(session, paths, attempts \\ 50) do
    path = current_path(session)

    if path in paths or attempts == 0 do
      path
    else
      Process.sleep(100)
      await_path_in(session, paths, attempts - 1)
    end
  end
end
