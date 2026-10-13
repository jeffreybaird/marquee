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
  import MarqueeFeatures.Support.Browser

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
    # Finishing navigates to the dashboard — wait for the wizard to be gone
    # before the next step reads the organization back.
    session =
      world.session
      |> await_live_connect()
      |> assert_has(css("[data-test=onboarding-step-1]"))
      |> click(css("[data-test=onboarding-next]"))
      |> assert_has(css("[data-test=onboarding-step-2]"))
      |> click(css("[data-test=onboarding-next]"))
      |> assert_has(css("[data-test=onboarding-step-3]"))
      |> click(css("[data-test=onboarding-next]"))
      |> assert_has(css("[data-test=onboarding-step-4]"))
      |> click(css("[data-test=onboarding-finish]"))

    # DEBUG-TEMP
    Process.sleep(3000)
    IO.puts("DEBUG url=#{current_url(session)}")
    IO.puts("DEBUG org=#{inspect(Repo.reload(world.org).onboarding_completed_at)}")
    IO.puts("DEBUG finish_present=#{has?(session, css("[data-test=onboarding-finish]"))}")
    IO.puts("DEBUG progress_present=#{has?(session, css("[data-test=onboarding-progress]"))}")
    IO.puts("DEBUG alert=#{inspect(all(session, css("[role=alert]")) |> Enum.map(&Wallaby.Element.text/1))}")
    IO.puts("DEBUG h1=#{inspect(all(session, css("h1")) |> Enum.map(&Wallaby.Element.text/1))}")

    session =
      session
      |> refute_has(css("[data-test=onboarding-progress]"))
      |> assert_has(css("h1", text: "Dashboard"))

    Map.put(world, :session, session)
  end)

  when_("I skip the setup wizard", fn world ->
    session =
      world.session
      |> await_live_connect()
      |> click(css("[data-test=onboarding-skip]"))
      |> refute_has(css("[data-test=onboarding-progress]"))

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
