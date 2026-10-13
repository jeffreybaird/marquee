defmodule MarqueeFeatures.Steps.Billing do
  @moduledoc """
  Step definitions for the viewer-billing features:

    * billing__coupon_management.feature
    * billing__stripe_connect_onboarding.feature
    * billing__subscription_plan_management.feature
    * billing__viewer_subscription_flow.feature

  Also owns "I click to connect my Stripe account" and "I am redirected to
  the Stripe OAuth flow", reused by admin_dashboard__organization_settings.

  Operators and viewers drive the real admin and viewer pages through
  Wallaby. Stripe is never called: `Marquee.Billing.MockStripeClient` is
  switched to Mox global mode (the LiveView and controller processes call
  it) and each stub reports its arguments back to the scenario process, so
  Then steps assert exactly what the platform asked Stripe to do.

  Stripe-hosted pages (Connect onboarding, Checkout, Customer Portal) are
  replaced by stub URLs on the test endpoint; a step asserts the browser was
  sent there. Stripe's side of the flow (payment, cancellation) is
  represented by signed webhooks POSTed to `/webhooks/stripe`.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Marquee.Factory
  import ExUnit.Assertions
  import MarqueeFeatures.Support.Browser
  import Plug.Conn, only: [put_req_header: 3]
  import Phoenix.ConnTest, only: [build_conn: 0, dispatch: 5]

  alias Marquee.Accounts.Organization
  alias Marquee.Billing
  alias Marquee.Billing.Coupon
  alias Marquee.Billing.MockStripeClient
  alias Marquee.Billing.Plan
  alias Marquee.Billing.ViewerSubscription
  alias Marquee.Repo
  alias Marquee.Viewers.Viewer
  alias Marquee.Viewers.ViewerToken

  @endpoint MarqueeWeb.Endpoint
  @webhook_secret "whsec_cucumber_billing_test_secret"

  # ==== Stripe Connect onboarding ===========================================

  given_ "my organization is not yet connected to Stripe", fn world ->
    org = Repo.reload!(world.org)
    refute org.stripe_connect_onboarding_complete
    Map.put(world, :org, org)
  end

  when_ "I click to connect my Stripe account", fn world ->
    world = stub_connect_onboarding(world)

    session =
      if current_path(world.session) == "/admin/settings" do
        await_live_connect(world.session)
      else
        visit_live(world.session, "/admin/settings?org=#{world.org.slug}")
      end

    session = click(session, css("[data-test=connect-stripe-btn]"))
    Map.put(world, :session, session)
  end

  then_ "I am redirected to the Stripe OAuth flow", fn world ->
    assert_receive {:stripe_connect_link, account_id, params}, 5_000

    assert URI.parse(params.return_url).path == "/admin/settings/stripe/return"
    assert URI.parse(params.refresh_url).path == "/admin/settings/stripe/refresh"
    assert Repo.reload!(world.org).stripe_connect_account_id == account_id

    await_url(world.session, onboarding_stub_url(account_id))
    world
  end

  given_ "I have completed the Stripe OAuth flow", fn world ->
    account_id = "acct_completed_#{System.unique_integer([:positive])}"
    org = update_org!(world.org, stripe_connect_account_id: account_id)
    me = self()

    use_stripe_mock()

    Mox.stub(MockStripeClient, :get_connect_account, fn id ->
      send(me, {:stripe_get_connect_account, id})
      {:ok, %{id: id, charges_enabled: true, details_submitted: true}}
    end)

    Map.merge(world, %{org: org, connect_account_id: account_id})
  end

  when_ "Stripe redirects me back to the platform", fn world ->
    session = visit(world.session, "/admin/settings/stripe/return?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  then_ "my organization is linked to a Stripe Connect account", fn world ->
    account_id = world.connect_account_id
    assert_receive {:stripe_get_connect_account, ^account_id}, 5_000

    assert_eventually(fn ->
      org = Repo.reload!(world.org)
      org.stripe_connect_onboarding_complete and org.stripe_connect_account_id == account_id
    end)

    Map.put(world, :org, Repo.reload!(world.org))
  end

  then_ "the Stripe Connect status shows as complete", fn world ->
    assert_has(
      world.session,
      css("[data-test=stripe-connected-status]", text: "Stripe connected")
    )

    assert_has(
      world.session,
      css("[data-test=stripe-connected-status]", text: world.connect_account_id)
    )

    world
  end

  then_ "I can receive viewer subscription payments", fn world ->
    org = Repo.reload!(world.org)
    assert Billing.ensure_stripe_connected(org) == :ok

    plan = insert(:plan, organization: org)
    viewer = insert(:viewer, organization: org)
    stub_checkout_session()

    assert {:ok, %{url: _}} = Billing.create_viewer_checkout(org, viewer, plan)
    assert_receive {:stripe_checkout_session, params}, 5_000
    assert params.stripe_connect_account_id == world.connect_account_id

    world
  end

  given_ "I started but did not complete Stripe Connect onboarding", fn world ->
    account_id = "acct_pending_#{System.unique_integer([:positive])}"

    org =
      update_org!(world.org,
        stripe_connect_account_id: account_id,
        stripe_connect_onboarding_complete: false
      )

    world
    |> Map.merge(%{org: org, connect_account_id: account_id})
    |> stub_connect_onboarding()
  end

  when_ "I return via the Stripe refresh callback", fn world ->
    session = visit(world.session, "/admin/settings/stripe/refresh?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  then_ "I am redirected to continue onboarding", fn world ->
    account_id = world.connect_account_id
    assert_receive {:stripe_connect_link, ^account_id, params}, 5_000
    refute_received {:stripe_connect_account_created, _}

    assert URI.parse(params.return_url).path == "/admin/settings/stripe/return"
    await_url(world.session, onboarding_stub_url(account_id))
    world
  end

  # ==== Subscription plan management ========================================

  when_ "I create a plan with a name, price, and description", fn world ->
    world = world |> connect_org() |> stub_plan_creation()

    session =
      world
      |> open_new_plan_form()
      |> fill_plan_form(
        name: "Premium Monthly",
        description: "Every title, every month.",
        amount: "12.99"
      )
      |> click(css("[data-test=plan-save-btn]"))
      |> assert_has(css("[data-test=plans-list]", text: "Premium Monthly"))

    Map.merge(world, %{session: session, plan_name: "Premium Monthly"})
  end

  then_ "a Stripe product and price are created in Stripe", fn world ->
    account_id = world.connect_account_id

    assert_receive {:stripe_product, product_params, [connect_account: ^account_id]}, 5_000
    assert product_params.name == "Premium Monthly"
    assert product_params.description == "Every title, every month."

    assert_receive {:stripe_price, price_params, [connect_account: ^account_id]}, 5_000
    assert price_params.unit_amount == 1299
    assert price_params.recurring == %{interval: "month"}

    plan = find_plan_by_name!(world.org, "Premium Monthly")
    assert plan.stripe_product_id == price_params.product
    assert plan.stripe_price_id =~ "price_cucumber_"
    assert plan.amount == 1299

    Map.put(world, :plan, plan)
  end

  then_ "the plan is available for viewers to subscribe to", fn world ->
    plan = find_plan_by_name!(world.org, world.plan_name)
    assert plan.active

    world = log_in_viewer(world, insert(:viewer, organization: world.org))

    session =
      world.session
      |> visit_live("/subscribe?org=#{world.org.slug}")
      |> assert_has(css("[data-test=plan-card-#{plan.id}]", text: world.plan_name))
      |> assert_has(css("[data-test=subscribe-btn-#{plan.id}]"))

    Map.put(world, :session, session)
  end

  when_ "I create a plan and specify a trial duration", fn world ->
    world = world |> connect_org() |> stub_plan_creation()

    session =
      world
      |> open_new_plan_form()
      |> fill_plan_form(name: "Trial Plan", description: "Try it free.", amount: "9.99")
      |> fill_in(css("[data-test=plan-trial-days-input]"), with: "14")
      |> click(css("[data-test=plan-save-btn]"))
      |> assert_has(css("[data-test=plans-list]", text: "14-day trial"))

    Map.merge(world, %{session: session, plan_name: "Trial Plan"})
  end

  then_ "new subscribers receive a trial period before being charged", fn world ->
    plan = find_plan_by_name!(world.org, world.plan_name)
    assert plan.trial_period_days == 14

    world = log_in_viewer(world, insert(:viewer, organization: world.org))
    stub_checkout_session()

    session =
      world.session
      |> visit_live("/subscribe?org=#{world.org.slug}")
      |> assert_has(css("[data-test=plan-card-#{plan.id}]", text: "14-day free trial"))
      |> click(css("[data-test=subscribe-btn-#{plan.id}]"))

    assert_receive {:stripe_checkout_session, params}, 5_000
    assert params.trial_period_days == 14
    assert params.line_items == [%{price: plan.stripe_price_id, quantity: 1}]

    Map.put(world, :session, session)
  end

  given_ "a plan exists", fn world ->
    world = connect_org(world)
    plan = insert(:plan, organization: world.org, name: "Basic", description: "Original")
    Map.put(world, :plan, plan)
  end

  when_ "I edit the plan name or description and save", fn world ->
    session =
      world.session
      |> visit_live("/admin/plans?org=#{world.org.slug}")
      |> click(css("[data-test=edit-plan-#{world.plan.id}]"))
      |> assert_has(css("[data-test=plan-name-input]"))
      |> fill_in(css("[data-test=plan-name-input]"), with: "Basic Plus")
      |> fill_in(css("[data-test=plan-description-input]"), with: "Now with more extras")
      |> click(css("[data-test=plan-save-btn]"))
      |> assert_has(css("[data-test=plan-row-#{world.plan.id}]", text: "Basic Plus"))

    Map.put(world, :session, session)
  end

  then_ "the plan record is updated", fn world ->
    plan = Billing.get_plan!(world.org, world.plan.id)
    assert plan.name == "Basic Plus"
    assert plan.description == "Now with more extras"
    assert plan.stripe_price_id == world.plan.stripe_price_id
    Map.put(world, :plan, plan)
  end

  given_ "an active plan exists with existing subscribers", fn world ->
    world = connect_org(world)
    plan = insert(:plan, organization: world.org, name: "Legacy Tier", active: true)
    subscriber = insert(:subscribed_viewer, organization: world.org)

    insert(:viewer_subscription,
      organization: world.org,
      viewer: subscriber,
      plan: plan,
      status: "active"
    )

    Map.merge(world, %{plan: plan, subscriber: subscriber})
  end

  when_ "I deactivate the plan", fn world ->
    session =
      world.session
      |> visit_live("/admin/plans?org=#{world.org.slug}")
      |> click(css("[data-test=deactivate-plan-#{world.plan.id}]"))
      |> assert_has(css("[data-test=reactivate-plan-#{world.plan.id}]"))

    Map.put(world, :session, session)
  end

  then_ "no new viewers can subscribe to it", fn world ->
    refute Billing.get_plan!(world.org, world.plan.id).active

    world = log_in_viewer(world, insert(:viewer, organization: world.org))

    session =
      world.session
      |> visit_live("/subscribe?org=#{world.org.slug}")
      |> assert_has(css("[data-test=plan-card-#{world.plan.id}]", count: 0))

    Map.put(world, :session, session)
  end

  then_ "existing subscribers retain their access", fn world ->
    world = log_in_viewer(world, world.subscriber)
    video = ready_video(world.org)

    assert_gated_access(world.session, world.org, video)
    Map.put(world, :video, video)
  end

  given_ "a plan exists with no active subscribers", fn world ->
    world = connect_org(world)
    plan = insert(:plan, organization: world.org, name: "Unused Tier")
    Map.put(world, :plan, plan)
  end

  when_ "I delete the plan", fn world ->
    session = visit_live(world.session, "/admin/plans?org=#{world.org.slug}")

    # accept_confirm/2 returns the dialog message, not the session.
    _message =
      accept_confirm(session, fn s ->
        click(s, css("[data-test=delete-plan-#{world.plan.id}]"))
      end)

    Map.put(world, :session, session)
  end

  then_ "it is removed from the system", fn world ->
    assert_has(world.session, css("[data-test=plan-row-#{world.plan.id}]", count: 0))

    %{results: plans} = Billing.list_plans(world.org)
    refute Enum.any?(plans, &(&1.id == world.plan.id))
    assert {:error, :not_found} = Billing.get_plan(world.org, world.plan.id)
    assert %DateTime{} = Repo.get!(Plan, world.plan.id).deleted_at

    world
  end

  # ==== Coupon management ===================================================

  when_ "I create a coupon with a code and a fixed discount amount", fn world ->
    world = world |> connect_org() |> stub_coupon_creation()

    session =
      world
      |> open_new_coupon_form()
      |> fill_in(css("[data-test=coupon-code-input]"), with: "FLAT5")
      |> fill_in(css("[data-test=coupon-name-input]"), with: "Five dollars off")
      |> click(button("Amount off"))
      |> fill_in(css("[data-test=coupon-amount-off-input]"), with: "5.00")
      |> click(css("[data-test=coupon-save-btn]"))
      |> assert_has(css("[data-test=coupons-list]", text: "FLAT5"))

    Map.merge(world, %{session: session, coupon_code: "FLAT5"})
  end

  then_ "the coupon is available for viewers to apply at checkout", fn world ->
    account_id = world.connect_account_id

    assert_receive {:stripe_coupon, coupon_params, [connect_account: ^account_id]}, 5_000
    assert coupon_params.amount_off == 500
    assert coupon_params.currency == "usd"

    assert_receive {:stripe_promotion_code, promo_params, [connect_account: ^account_id]},
                   5_000

    assert promo_params.code == "FLAT5"

    coupon = find_coupon_by_code!(world.org, "FLAT5")
    assert coupon.active
    assert coupon.amount_off == 500
    assert coupon.stripe_coupon_id == promo_params.coupon
    assert coupon.stripe_promotion_code_id =~ "promo_cucumber_"

    Map.put(world, :coupon, coupon)
  end

  when_ "I create a coupon with a code and a percentage discount", fn world ->
    world = world |> connect_org() |> stub_coupon_creation()

    session =
      world
      |> open_new_coupon_form()
      |> fill_in(css("[data-test=coupon-code-input]"), with: "QUARTER")
      |> fill_in(css("[data-test=coupon-name-input]"), with: "Quarter off")
      |> fill_in(css("[data-test=coupon-percent-off-input]"), with: "25")
      |> click(css("[data-test=coupon-save-btn]"))
      |> assert_has(css("[data-test=coupons-list]", text: "QUARTER"))

    Map.merge(world, %{session: session, coupon_code: "QUARTER"})
  end

  then_ "the coupon reduces the plan price by that percentage at checkout", fn world ->
    account_id = world.connect_account_id

    assert_receive {:stripe_coupon, coupon_params, [connect_account: ^account_id]}, 5_000
    assert Decimal.equal?(Decimal.new(to_string(coupon_params.percent_off)), Decimal.new(25))
    refute Map.has_key?(coupon_params, :amount_off)

    assert_receive {:stripe_promotion_code, promo_params, [connect_account: ^account_id]},
                   5_000

    assert promo_params.code == "QUARTER"

    coupon = find_coupon_by_code!(world.org, "QUARTER")
    assert coupon.active
    assert Decimal.equal?(coupon.percent_off, Decimal.new(25))

    Map.put(world, :coupon, coupon)
  end

  given_ "a coupon code exists and is active", fn world ->
    world = connect_org(world)
    plan = insert(:plan, organization: world.org, name: "Coupon Plan", amount: 2000)
    coupon = insert(:coupon, organization: world.org, code: "SAVE20", active: true)
    Map.merge(world, %{plan: plan, coupon: coupon})
  end

  given_ "an invalid or deactivated coupon code", fn world ->
    world = connect_org(world)
    plan = insert(:plan, organization: world.org, name: "Coupon Plan", amount: 2000)
    coupon = insert(:coupon, organization: world.org, code: "EXPIRED10", active: false)
    Map.merge(world, %{plan: plan, coupon: coupon})
  end

  when_ "a viewer enters the code during checkout", fn world ->
    world = log_in_viewer(world, insert(:viewer, organization: world.org))
    stub_checkout_session()

    session =
      world.session
      |> visit_live("/subscribe?org=#{world.org.slug}")
      |> fill_in(css("[data-test=checkout-coupon-input]"), with: world.coupon.code)
      |> click(css("[data-test=subscribe-btn-#{world.plan.id}]"))

    Map.put(world, :session, session)
  end

  then_ "the discount is applied to the subscription price", fn world ->
    assert_receive {:stripe_checkout_session, params}, 5_000
    assert params.line_items == [%{price: world.plan.stripe_price_id, quantity: 1}]
    assert params[:discounts] == [%{promotion_code: world.coupon.stripe_promotion_code_id}]

    await_url(world.session, checkout_stub_url())
    world
  end

  then_ "an error is displayed and no discount is applied", fn world ->
    assert_has(world.session, css("[data-test=checkout-coupon-error]"))

    receive do
      {:stripe_checkout_session, params} -> assert params[:discounts] in [nil, []]
    after
      0 -> :ok
    end

    world
  end

  given_ "an active coupon exists", fn world ->
    world = connect_org(world)
    coupon = insert(:coupon, organization: world.org, code: "SPRING", active: true)
    Map.put(world, :coupon, coupon)
  end

  when_ "I deactivate it", fn world ->
    me = self()
    use_stripe_mock()

    Mox.stub(MockStripeClient, :deactivate_connected_coupon, fn coupon_id, opts ->
      send(me, {:stripe_deactivate_coupon, coupon_id, opts})
      {:ok, %{id: coupon_id}}
    end)

    session =
      world.session
      |> visit_live("/admin/coupons?org=#{world.org.slug}")
      |> click(css("[data-test=deactivate-coupon-#{world.coupon.id}]"))
      |> assert_has(css("[data-test=deactivate-coupon-#{world.coupon.id}]", count: 0))

    Map.put(world, :session, session)
  end

  then_ "the coupon code can no longer be applied at checkout", fn world ->
    refute Repo.get!(Coupon, world.coupon.id).active

    # The code is redeemed on Stripe's hosted Checkout (allow_promotion_codes),
    # so it stays usable there until the platform deactivates it in Stripe.
    stripe_coupon_id = world.coupon.stripe_coupon_id
    account_id = world.connect_account_id

    assert_receive {:stripe_deactivate_coupon, ^stripe_coupon_id,
                    [connect_account: ^account_id]},
                   5_000

    world
  end

  # ==== Viewer subscription flow ============================================

  given_ "I am a registered viewer on a tenant site", fn world ->
    org = insert(:organization) |> connect_organization()
    viewer = insert(:viewer, organization: org)

    world
    |> Map.merge(%{org: org, connect_account_id: org.stripe_connect_account_id})
    |> log_in_viewer(viewer)
  end

  given_ "at least one active plan is available", fn world ->
    plan = insert(:plan, organization: world.org, name: "All Access", active: true)
    Map.put(world, :plan, plan)
  end

  when_ "I select a plan on the subscribe page", fn world ->
    select_plan_on_subscribe_page(world)
  end

  then_ "I am redirected to Stripe Checkout", fn world ->
    assert_receive {:stripe_checkout_session, params}, 5_000
    assert params.line_items == [%{price: world.plan.stripe_price_id, quantity: 1}]
    assert params.viewer_id == world.viewer.id
    assert params.stripe_connect_account_id == world.connect_account_id
    assert URI.parse(params.success_url).path == "/subscribe/success"
    assert URI.parse(params.cancel_url).path == "/subscribe"

    await_url(world.session, checkout_stub_url())
    Map.put(world, :checkout_params, params)
  end

  then_ "upon successful payment my subscription becomes active", fn world ->
    sub_id = "sub_checkout_#{System.unique_integer([:positive])}"
    customer_id = "cus_checkout_#{System.unique_integer([:positive])}"

    conn =
      post_signed_stripe_event(
        "checkout.session.completed",
        %{
          "object" => "checkout.session",
          "id" => "cs_test_#{System.unique_integer([:positive])}",
          "mode" => "subscription",
          "status" => "complete",
          "payment_status" => "paid",
          "customer" => customer_id,
          "customer_email" => world.viewer.email,
          "subscription" => sub_id
        },
        world.connect_account_id
      )

    assert conn.status == 200

    session =
      world.session
      |> visit(world.checkout_params.success_url)
      |> assert_has(css("[data-test=subscribe-success]"))

    assert {:ok, %ViewerSubscription{status: "active"} = sub} =
             Billing.get_viewer_subscription_by_stripe_id(world.org, sub_id)

    assert sub.viewer_id == world.viewer.id
    assert Repo.reload!(world.viewer).subscription_status == "active"

    Map.merge(world, %{session: session, viewer_subscription: sub})
  end

  then_ "I gain access to gated content", fn world ->
    video = ready_video(world.org)
    assert_gated_access(world.session, world.org, video)
    Map.put(world, :video, video)
  end

  given_ "I am on the Stripe Checkout page", fn world ->
    plan = insert(:plan, organization: world.org, name: "All Access", active: true)
    world = world |> Map.put(:plan, plan) |> select_plan_on_subscribe_page()

    assert_receive {:stripe_checkout_session, params}, 5_000
    await_url(world.session, checkout_stub_url())
    Map.put(world, :checkout_params, params)
  end

  when_ "I cancel and return to the platform", fn world ->
    session = visit(world.session, world.checkout_params.cancel_url)
    Map.put(world, :session, session)
  end

  then_ "no subscription is created", fn world ->
    assert {:error, :not_found} = Billing.get_active_viewer_subscription(world.org, world.viewer)
    assert Repo.reload!(world.viewer).subscription_status == "none"
    world
  end

  then_ "I am returned to the subscribe page", fn world ->
    session =
      world.session
      |> await_live_connect()
      |> assert_has(css("[data-test=plan-card-#{world.plan.id}]"))

    assert current_path(session) == "/subscribe"
    Map.put(world, :session, session)
  end

  given_ "I have an active subscription", fn world ->
    give_viewer_subscription(world, "active")
  end

  when_ "I click \"Manage Subscription\" from my account page", fn world ->
    stub_portal_session()

    session =
      world.session
      |> visit_live("/account?org=#{world.org.slug}")
      |> assert_has(css("[data-test=manage-subscription-btn]", text: "Manage subscription"))
      |> click(css("[data-test=manage-subscription-btn]"))

    Map.put(world, :session, session)
  end

  then_ "I am redirected to the Stripe Customer Portal", fn world ->
    world = assert_portal_session_for_viewer(world)
    await_url(world.session, portal_stub_url())
    world
  end

  then_ "I can update my payment method or cancel my subscription", fn world ->
    # Payment-method updates and cancellation happen on the Stripe-hosted
    # portal; the platform's part is opening a portal session for this
    # viewer's Stripe customer on the org's connected account, returning to
    # the account page.
    assert %{customer: customer, return_url: return_url} = world.portal_params
    assert customer == Repo.reload!(world.viewer).stripe_customer_id
    assert URI.parse(return_url).path == "/account"
    assert world.portal_opts == [connect_account: world.connect_account_id]
    world
  end

  when_ "I cancel through the Stripe Customer Portal", fn world ->
    stub_portal_session()

    session =
      world.session
      |> visit_live("/account?org=#{world.org.slug}")
      |> click(css("[data-test=manage-subscription-btn]"))

    world = world |> Map.put(:session, session) |> assert_portal_session_for_viewer()
    await_url(world.session, portal_stub_url())
    world
  end

  then_ "Stripe sends a cancellation webhook", fn world ->
    sub = world.viewer_subscription
    now = System.system_time(:second)

    conn =
      post_signed_stripe_event(
        "customer.subscription.deleted",
        subscription_object(sub, %{
          "status" => "canceled",
          "canceled_at" => now,
          "current_period_end" => now
        }),
        world.connect_account_id
      )

    assert conn.status == 200
    world
  end

  then_ "my subscription status is updated to cancelled", fn world ->
    sub = Repo.reload!(world.viewer_subscription)
    assert sub.status == "canceled"
    assert Repo.reload!(world.viewer).subscription_status == "canceled"

    session =
      world.session
      |> visit_live("/account?org=#{world.org.slug}")
      |> assert_has(css("[data-test=subscription-canceled-status]"))

    Map.merge(world, %{session: session, viewer_subscription: sub})
  end

  then_ "I lose access to gated content at the end of the billing period", fn world ->
    video = ready_video(world.org)
    assert_gated_redirect(world.session, world.org, video, ["/subscribe"])
    world
  end

  when_ "Stripe reports a failed payment via webhook", fn world ->
    conn =
      post_signed_stripe_event(
        "invoice.payment_failed",
        invoice_object(world.viewer_subscription, "open"),
        world.connect_account_id
      )

    assert conn.status == 200
    world
  end

  then_ "my account shows a payment issue notice", fn world ->
    session =
      world.session
      |> visit_live("/account?org=#{world.org.slug}")
      |> assert_has(css("[data-test=subscription-past-due-status]"))

    Map.put(world, :session, session)
  end

  then_ "I am directed to resolve the issue", fn world ->
    assert_has(world.session, css("[data-test=update-payment-btn]"))

    video = ready_video(world.org)
    session = assert_gated_redirect(world.session, world.org, video, ["/account/payment-issue"])

    session =
      session
      |> assert_has(css("[data-test=payment-issue-page]"))
      |> assert_has(css("[data-test=update-payment-btn]"))

    Map.put(world, :session, session)
  end

  given_ "my subscription has a payment failure", fn world ->
    give_viewer_subscription(world, "past_due")
  end

  when_ "I update my payment method via the Stripe portal", fn world ->
    stub_portal_session()

    session =
      world.session
      |> visit_live("/account/payment-issue?org=#{world.org.slug}")
      |> click(css("[data-test=update-payment-btn]"))

    world = world |> Map.put(:session, session) |> assert_portal_session_for_viewer()
    await_url(world.session, portal_stub_url())
    world
  end

  when_ "payment succeeds", fn world ->
    conn =
      post_signed_stripe_event(
        "invoice.payment_succeeded",
        invoice_object(world.viewer_subscription, "paid"),
        world.connect_account_id
      )

    assert conn.status == 200
    world
  end

  then_ "my subscription status returns to active", fn world ->
    assert Repo.reload!(world.viewer_subscription).status == "active"
    assert Repo.reload!(world.viewer).subscription_status == "active"
    world
  end

  then_ "my access is restored", fn world ->
    video = ready_video(world.org)
    assert_gated_access(world.session, world.org, video)
    world
  end

  given_ "a video requires a subscription", fn world ->
    Map.put(world, :video, ready_video(world.org))
  end

  when_ "an unauthenticated viewer attempts to access it", fn world ->
    session =
      world
      |> fresh_browser_session()
      |> visit("/watch/#{world.video.id}?org=#{world.org.slug}")

    Map.put(world, :session, session)
  end

  then_ "they are redirected to the login or subscribe page", fn world ->
    path = await_path_in(world.session, ["/login", "/subscribe"])
    assert path in ["/login", "/subscribe"]
    world
  end

  # ==== Helpers: Stripe mock ================================================

  # The LiveView, controller and Oban processes call the mock, so expectations
  # are global and owned by the scenario process (Cucumberex runs every
  # scenario in the same process). Each stub reports back to that process.
  defp use_stripe_mock do
    Mox.set_mox_global()
    :ok
  end

  defp stub_connect_onboarding(world) do
    me = self()
    use_stripe_mock()
    drain_connect_onboarding_messages()

    Mox.stub(MockStripeClient, :create_connect_account, fn params ->
      account_id = "acct_cucumber_#{System.unique_integer([:positive])}"
      send(me, {:stripe_connect_account_created, params})
      {:ok, %{id: account_id}}
    end)

    Mox.stub(MockStripeClient, :create_connect_account_link, fn account_id, params ->
      send(me, {:stripe_connect_link, account_id, params})
      {:ok, %{url: onboarding_stub_url(account_id)}}
    end)

    world
  end

  # Scenarios share one process, so drop reports left by an earlier
  # scenario's stubs before asserting on what this scenario asked Stripe.
  defp drain_connect_onboarding_messages do
    receive do
      {:stripe_connect_account_created, _} -> drain_connect_onboarding_messages()
      {:stripe_connect_link, _, _} -> drain_connect_onboarding_messages()
    after
      0 -> :ok
    end
  end

  defp stub_plan_creation(world) do
    me = self()
    use_stripe_mock()

    Mox.stub(MockStripeClient, :create_connected_product, fn params, opts ->
      send(me, {:stripe_product, params, opts})
      {:ok, %{id: "prod_cucumber_#{System.unique_integer([:positive])}"}}
    end)

    Mox.stub(MockStripeClient, :create_connected_price, fn params, opts ->
      send(me, {:stripe_price, params, opts})
      {:ok, %{id: "price_cucumber_#{System.unique_integer([:positive])}"}}
    end)

    world
  end

  defp stub_coupon_creation(world) do
    me = self()
    use_stripe_mock()

    Mox.stub(MockStripeClient, :create_connected_coupon, fn params, opts ->
      send(me, {:stripe_coupon, params, opts})
      {:ok, %{id: "coupon_cucumber_#{System.unique_integer([:positive])}"}}
    end)

    Mox.stub(MockStripeClient, :create_connected_promotion_code, fn params, opts ->
      send(me, {:stripe_promotion_code, params, opts})
      {:ok, %{id: "promo_cucumber_#{System.unique_integer([:positive])}"}}
    end)

    world
  end

  defp stub_checkout_session do
    me = self()
    use_stripe_mock()

    Mox.stub(MockStripeClient, :create_connected_checkout_session, fn params ->
      send(me, {:stripe_checkout_session, params})
      {:ok, %{id: "cs_cucumber_#{System.unique_integer([:positive])}", url: checkout_stub_url()}}
    end)

    :ok
  end

  defp stub_portal_session do
    me = self()
    use_stripe_mock()

    Mox.stub(MockStripeClient, :create_connected_portal_session, fn params, opts ->
      send(me, {:stripe_portal_session, params, opts})
      {:ok, %{id: "bps_cucumber", url: portal_stub_url()}}
    end)

    :ok
  end

  defp assert_portal_session_for_viewer(world) do
    assert_receive {:stripe_portal_session, params, opts}, 5_000
    assert params.customer == Repo.reload!(world.viewer).stripe_customer_id
    assert opts == [connect_account: world.connect_account_id]
    Map.merge(world, %{portal_params: params, portal_opts: opts})
  end

  # Stripe-hosted pages are stood in for by paths on the test endpoint (they
  # 404); the browser landing on them proves the external redirect happened.
  defp onboarding_stub_url(account_id), do: "#{base_url()}/__stripe_stub/connect/#{account_id}"
  defp checkout_stub_url, do: "#{base_url()}/__stripe_stub/checkout"
  defp portal_stub_url, do: "#{base_url()}/__stripe_stub/billing-portal"

  defp base_url, do: Application.get_env(:wallaby, :base_url)

  # ==== Helpers: webhooks ===================================================

  defp post_signed_stripe_event(type, object, connect_account_id) do
    Application.put_env(:marquee, :stripe_webhook_secret, @webhook_secret)
    Application.put_env(:marquee, :stripe_connect_webhook_secret, @webhook_secret)

    payload =
      Jason.encode!(%{
        "id" => "evt_cucumber_#{System.unique_integer([:positive])}",
        "object" => "event",
        "api_version" => "2024-06-20",
        "created" => System.system_time(:second),
        "livemode" => false,
        "type" => type,
        "account" => connect_account_id,
        "data" => %{"object" => object}
      })

    timestamp = System.system_time(:second)

    signature =
      :crypto.mac(:hmac, :sha256, @webhook_secret, "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", "t=#{timestamp},v1=#{signature}")
    |> put_req_header("stripe-account", connect_account_id)
    |> dispatch(@endpoint, :post, "/webhooks/stripe", payload)
  end

  defp subscription_object(%ViewerSubscription{} = sub, overrides) do
    sub = Repo.preload(sub, :plan)

    Map.merge(
      %{
        "object" => "subscription",
        "id" => sub.stripe_subscription_id,
        "customer" => sub.stripe_customer_id,
        "status" => sub.status,
        "cancel_at_period_end" => false,
        "items" => %{
          "object" => "list",
          "data" => [
            %{
              "object" => "subscription_item",
              "id" => "si_cucumber",
              "price" => %{"object" => "price", "id" => sub.plan && sub.plan.stripe_price_id}
            }
          ]
        }
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

  # ==== Helpers: data =======================================================

  defp connect_org(world) do
    org = connect_organization(world.org)
    Map.merge(world, %{org: org, connect_account_id: org.stripe_connect_account_id})
  end

  defp connect_organization(%Organization{} = org) do
    update_org!(org,
      stripe_connect_account_id: "acct_cucumber_#{System.unique_integer([:positive])}",
      stripe_connect_onboarding_complete: true
    )
  end

  defp update_org!(%Organization{} = org, changes) do
    org |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  defp give_viewer_subscription(world, status) do
    plan =
      Map.get_lazy(world, :plan, fn ->
        insert(:plan, organization: world.org, name: "All Access", active: true)
      end)

    customer_id = "cus_cucumber_#{System.unique_integer([:positive])}"

    viewer =
      world.viewer
      |> Repo.reload!()
      |> Ecto.Changeset.change(stripe_customer_id: customer_id)
      |> Repo.update!()
      |> Viewer.subscription_changeset(%{subscription_status: status})
      |> Repo.update!()

    sub =
      insert(:viewer_subscription,
        organization: world.org,
        viewer: viewer,
        plan: plan,
        stripe_customer_id: customer_id,
        status: status
      )

    Map.merge(world, %{plan: plan, viewer: viewer, viewer_subscription: sub})
  end

  defp find_plan_by_name!(org, name) do
    %{results: plans} = Billing.list_plans(org, per_page: 100)
    Enum.find(plans, &(&1.name == name)) || flunk("no plan named #{inspect(name)}")
  end

  defp find_coupon_by_code!(org, code) do
    %{results: coupons} = Billing.list_coupons(org, per_page: 100)

    Enum.find(coupons, &(String.upcase(&1.code) == code)) ||
      flunk("no coupon with code #{inspect(code)}")
  end

  defp ready_video(org) do
    insert(:video, organization: org, mux_status: "ready", published: true, duration: 600.0)
  end

  # ==== Helpers: browser ====================================================

  defp open_new_plan_form(world) do
    world.session
    |> visit_live("/admin/plans?org=#{world.org.slug}")
    |> click(css("[data-test=new-plan-btn]"))
    |> assert_has(css("[data-test=plan-name-input]"))
  end

  defp fill_plan_form(session, fields) do
    session
    |> fill_in(css("[data-test=plan-name-input]"), with: fields[:name])
    |> fill_in(css("[data-test=plan-description-input]"), with: fields[:description])
    |> fill_in(css("[data-test=plan-amount-input]"), with: fields[:amount])
    |> select_option("[data-test=plan-interval-select]", "monthly")
  end

  defp open_new_coupon_form(world) do
    world.session
    |> visit_live("/admin/coupons?org=#{world.org.slug}")
    |> click(css("[data-test=new-coupon-btn]"))
    |> assert_has(css("[data-test=coupon-code-input]"))
  end

  defp select_plan_on_subscribe_page(world) do
    stub_checkout_session()

    session =
      world.session
      |> visit_live("/subscribe?org=#{world.org.slug}")
      |> click(css("[data-test=subscribe-btn-#{world.plan.id}]"))

    Map.put(world, :session, session)
  end

  # Signs `viewer` in to its org's viewer site through a magic link, in a
  # fresh browser (an operator's admin login would otherwise put the viewer
  # site into member-preview mode).
  defp log_in_viewer(world, %Viewer{} = viewer) do
    {encoded_token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
    Repo.insert!(viewer_token)

    session =
      world
      |> fresh_browser_session()
      |> visit("/magic-link/#{encoded_token}?org=#{world.org.slug}")
      |> assert_has(css("[data-test=viewer-sign-out]"))

    Map.merge(world, %{viewer: viewer, session: session})
  end

  defp fresh_browser_session(world) do
    Wallaby.end_session(world.session)
    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)
    session
  end

  defp assert_gated_access(session, org, video) do
    path = "/watch/#{video.id}"
    session = visit_live(session, "#{path}?org=#{org.slug}")
    assert current_path(session) == path
    session
  end

  defp assert_gated_redirect(session, org, video, expected_paths) do
    session = visit(session, "/watch/#{video.id}?org=#{org.slug}")
    path = await_path_in(session, expected_paths)
    assert path in expected_paths, "expected redirect to #{inspect(expected_paths)}, got #{path}"
    session
  end

  defp await_url(session, expected, attempts \\ 50) do
    url = current_url(session)

    cond do
      url == expected ->
        session

      attempts == 0 ->
        flunk("expected browser at #{expected}, but it is at #{url}")

      true ->
        Process.sleep(100)
        await_url(session, expected, attempts - 1)
    end
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

  defp assert_eventually(fun, attempts \\ 50) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        flunk("condition never became true")

      true ->
        Process.sleep(100)
        assert_eventually(fun, attempts - 1)
    end
  end
end
