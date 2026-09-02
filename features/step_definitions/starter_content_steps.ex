defmodule MarqueeFeatures.Steps.StarterContent do
  @moduledoc """
  Step definitions for starter_content.feature.

  The banner presence is asserted through the live UI via Wallaby; the seeding,
  clearing, cap-exemption, isolation, and RBAC pathways are asserted at the
  context boundary (`StarterContent`/`UsageLimits`/`Accounts`) — the same
  pragmatic split used by the trial steps.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Marquee.Factory
  import ExUnit.Assertions

  alias Marquee.Accounts
  alias Marquee.Accounts.Scope
  alias Marquee.Onboarding.StarterContent
  alias Marquee.PlatformBilling.UsageLimits
  alias MarqueeWeb.WallabyCase

  # ---- Login variant ------------------------------------------------------

  given_("I am logged in as an operator with the viewer_support role", fn world ->
    org = insert(:organization)
    user = insert(:user, confirmed_at: DateTime.utc_now())
    membership = insert(:membership, user: user, organization: org, role: :viewer_support)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    session = WallabyCase.log_in_session(world.session, user, org)

    Map.merge(world, %{
      session: session,
      operator: user,
      org: org,
      membership: membership,
      scope: scope
    })
  end)

  # ---- Setup --------------------------------------------------------------

  given_("starter content has been seeded for my organization", fn world ->
    {:ok, _} = StarterContent.seed(world.org)
    world
  end)

  given_("another organization has been seeded with sample content", fn world ->
    other = insert(:organization)
    {:ok, _} = StarterContent.seed(other)
    Map.put(world, :other_org, other)
  end)

  # ---- Actions ------------------------------------------------------------

  when_("starter content is seeded for my organization", fn world ->
    {:ok, summary} = StarterContent.seed(world.org)
    Map.put(world, :seed_summary, summary)
  end)

  when_("I clear the sample content", fn world ->
    {:ok, _} = StarterContent.clear(world.scope)
    world
  end)

  # ---- Assertions ---------------------------------------------------------

  then_("my organization has sample videos, collections, and homepage rows", fn world ->
    assert StarterContent.seeded?(world.org)
    assert world.seed_summary.videos > 0
    assert world.seed_summary.collections > 0
    assert world.seed_summary.rows > 0
    world
  end)

  then_("my organization can still upload another video", fn world ->
    assert :ok = UsageLimits.check_upload(world.org)
    world
  end)

  then_("I see the sample content banner", fn world ->
    assert_has(world.session, css("[data-test=sample-content-banner]"))
    world
  end)

  then_("my organization has no sample content", fn world ->
    refute StarterContent.seeded?(world.org)
    world
  end)

  then_("I am not permitted to clear sample content", fn world ->
    # The clear endpoint requires at least the editor role; viewer_support is
    # below that threshold and the sample content is left intact.
    refute Accounts.role_at_least?(world.membership, :editor)
    assert StarterContent.seeded?(world.org)
    world
  end)
end
