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
    # Each wizard step renders its own "next" button, so gate every click on
    # the marker of the step it should land on; otherwise a click can find
    # the previous step's button an instant before LiveView patches it out.
    # Finishing navigates to the dashboard — wait for the dashboard heading
    # (and for the wizard to be gone) before the next step reads the
    # organization back.
    session =
      world.session
      |> await_connected_wizard()
      |> assert_has(css("[data-test=onboarding-step-1]"))
      |> click(css("[data-test=onboarding-next]"))
      |> assert_has(css("[data-test=onboarding-step-2]"))
      |> click(css("[data-test=onboarding-next]"))
      |> assert_has(css("[data-test=onboarding-step-3]"))
      |> click(css("[data-test=onboarding-next]"))
      |> assert_has(css("[data-test=onboarding-step-4]"))
      |> click(css("[data-test=onboarding-finish]"))
      |> assert_has(css("h1", text: "Dashboard"))
      |> refute_has(css("[data-test=onboarding-progress]"))

    Map.put(world, :session, session)
  end)

  when_("I skip the setup wizard", fn world ->
    session =
      world.session
      |> await_connected_wizard()
      |> click(css("[data-test=onboarding-skip]"))
      |> assert_has(css("h1", text: "Dashboard"))
      |> refute_has(css("[data-test=onboarding-progress]"))

    Map.put(world, :session, session)
  end)

  # The dashboard visit lands on /admin, whose LiveView then live-navigates to
  # the wizard. `await_live_connect/1` can match the dashboard's connected root
  # before that navigation completes, so a click sent then is dropped. Wait
  # until the connected root itself contains the wizard.
  defp await_connected_wizard(session) do
    assert_has(session, css("[data-phx-main].phx-connected [data-test=onboarding-progress]"))
  end

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
