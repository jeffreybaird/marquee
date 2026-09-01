defmodule MarqueeFeatures.Steps.Onboarding do
  @moduledoc """
  Step definitions for onboarding.feature.

  The wizard is driven through the live UI via Wallaby. "I visit the admin
  dashboard" is shared (defined in the trial steps); the gate redirects a
  not-yet-onboarded owner/admin to the wizard.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Marquee.Factory
  import ExUnit.Assertions

  alias Marquee.Accounts
  alias Marquee.Repo

  # ---- Setup --------------------------------------------------------------

  given_("my organization has not completed onboarding", fn world ->
    org =
      world.org
      |> Ecto.Changeset.change(onboarding_completed_at: nil)
      |> Repo.update!()

    Map.put(world, :org, org)
  end)

  given_("another organization has not completed onboarding", fn world ->
    insert(:organization, onboarding_completed_at: nil)
    world
  end)

  # ---- Actions ------------------------------------------------------------

  when_("I finish the setup wizard", fn world ->
    session =
      world.session
      |> click(css("[data-test=onboarding-next]"))
      |> click(css("[data-test=onboarding-next]"))
      |> click(css("[data-test=onboarding-next]"))
      |> click(css("[data-test=onboarding-finish]"))

    Map.put(world, :session, session)
  end)

  when_("I skip the setup wizard", fn world ->
    session = click(world.session, css("[data-test=onboarding-skip]"))
    Map.put(world, :session, session)
  end)

  # ---- Assertions ---------------------------------------------------------

  then_("I am taken to the setup wizard", fn world ->
    assert_has(world.session, css("[data-test=onboarding-progress]"))
    world
  end)

  then_("I am not shown the setup wizard", fn world ->
    refute_has(world.session, css("[data-test=onboarding-progress]"))
    world
  end)

  then_("onboarding is marked complete for my organization", fn world ->
    assert Accounts.onboarding_complete?(Repo.reload(world.org))
    world
  end)
end
