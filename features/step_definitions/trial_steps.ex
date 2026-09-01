defmodule MarqueeFeatures.Steps.Trial do
  @moduledoc """
  Step definitions for trial.feature.

  Banner and viewer-registration pathways are exercised through the live UI via
  Wallaby. The upload-duration, custom-domain, and "still watchable" pathways
  are asserted at the context boundary (`UsageLimits`/`PlatformBilling`) — a
  pragmatic concession, matching the auth steps: the operator has no
  Mux/custom-domain UI to drive, and the enforcement lives in the context.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Marquee.Factory
  import ExUnit.Assertions

  alias Marquee.Accounts
  alias Marquee.Content
  alias Marquee.PlatformBilling
  alias Marquee.PlatformBilling.UsageLimits

  # ---- Trial setup --------------------------------------------------------

  given_("my organization is on an active trial", fn world ->
    {:ok, _sub} = PlatformBilling.start_trial(world.org)
    world
  end)

  given_("my organization's trial has expired", fn world ->
    past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

    insert(:platform_subscription,
      organization: world.org,
      platform_plan: nil,
      stripe_subscription_id: nil,
      status: :past_due,
      trial_end: past
    )

    world
  end)

  given_("my organization already has 10 viewers", fn world ->
    for _ <- 1..10, do: insert(:viewer, organization: world.org)
    world
  end)

  given_("my organization already has 5 hours of ready video", fn world ->
    insert(:video, organization: world.org, mux_status: "ready", duration: 18_000.0)
    world
  end)

  given_("another organization has an expired trial", fn world ->
    other = insert(:organization)
    past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

    insert(:platform_subscription,
      organization: other,
      platform_plan: nil,
      stripe_subscription_id: nil,
      status: :past_due,
      trial_end: past
    )

    world
  end)

  # ---- Actions ------------------------------------------------------------

  when_("I visit the admin dashboard", fn world ->
    Map.put(world, :session, visit(world.session, "/admin?org=#{world.org.slug}"))
  end)

  when_("a new viewer tries to register on the viewer site", fn world ->
    session =
      world.session
      |> visit("/register?org=#{world.org.slug}")
      |> fill_in(css("[data-test=register-email-input]"), with: "late@example.com")
      |> click(css("[data-test=register-submit-btn]"))

    Map.put(world, :session, session)
  end)

  when_("I try to upload another video", fn world ->
    result = Content.create_upload_url(world.scope, %{title: "Over the cap"})
    Map.put(world, :upload_result, result)
  end)

  # ---- Assertions ---------------------------------------------------------

  then_("my organization is on a trialing subscription", fn world ->
    org = registered_org(world)
    assert {:ok, sub} = PlatformBilling.get_subscription(org)
    assert sub.status == :trialing
    Map.put(world, :org, org)
  end)

  then_("no payment information was collected", fn world ->
    {:ok, sub} = PlatformBilling.get_subscription(world.org)
    assert is_nil(sub.stripe_customer_id)
    assert is_nil(sub.stripe_subscription_id)
    world
  end)

  then_("I see the active trial banner", fn world ->
    assert_has(world.session, css("[data-test=trial-banner-active]"))
    world
  end)

  then_("I see the expired trial banner", fn world ->
    assert_has(world.session, css("[data-test=trial-banner-expired]"))
    world
  end)

  then_("I do not see the expired trial banner", fn world ->
    refute_has(world.session, css("[data-test=trial-banner-expired]"))
    world
  end)

  then_("the viewer registration is refused", fn world ->
    assert_text(world.session, "isn't accepting new members")
    world
  end)

  then_("the upload is refused with a plan-limit message", fn world ->
    assert {:error, :plan_limit_reached, %{unit: :seconds}} = world.upload_result
    world
  end)

  then_("my organization is not permitted a custom domain", fn world ->
    refute UsageLimits.can_use_custom_domain?(world.org)
    world
  end)

  then_("existing viewers can still watch published videos", fn world ->
    video = insert(:video, organization: world.org, mux_status: "ready", duration: 60.0)
    # The read/watch path is untouched by soft-lock: a ready video is still served.
    assert {:ok, %Content.Video{}} = Content.get_video(world.org, video.id)
    world
  end)

  # ---- Helpers ------------------------------------------------------------

  defp registered_org(world) do
    world.email
    |> Accounts.get_user_by_email()
    |> Accounts.get_user_primary_organization()
  end
end
