defmodule MarqueeFeatures.Steps.AdminOnboardingTour do
  @moduledoc """
  Step definitions for admin_onboarding_tour.feature.

  The guided tour is a Shepherd.js walkthrough that auto-launches for an
  operator who hasn't seen it. Completion is recorded per membership
  (`admin_tour_completed_at`), so the tour is scoped to one operator in one
  organization. Login and "I visit the admin dashboard" are shared steps.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import ExUnit.Assertions

  alias Marquee.Accounts
  alias Marquee.Repo

  # ---- Setup --------------------------------------------------------------

  given_("I have already completed the guided tour", fn world ->
    {:ok, _} = Accounts.complete_admin_tour(world.membership)
    world
  end)

  given_("I have not yet seen the guided tour", fn world ->
    membership =
      world.membership
      |> Ecto.Changeset.change(admin_tour_completed_at: nil)
      |> Repo.update!()

    Map.put(world, :membership, membership)
  end)

  # ---- Actions ------------------------------------------------------------

  when_("I dismiss the guided tour", fn world ->
    session = click(world.session, css(".shepherd-cancel-icon"))
    Map.put(world, :session, session)
  end)

  when_("I click the take a tour link", fn world ->
    session = click(world.session, css("[data-test=restart-tour]"))
    Map.put(world, :session, session)
  end)

  # ---- Assertions ---------------------------------------------------------

  then_("I am greeted by the guided tour", fn world ->
    assert_has(world.session, css(".shepherd-element", text: "Welcome"))
    world
  end)

  then_("the guided tour does not launch", fn world ->
    refute_has(world.session, css(".shepherd-element"))
    world
  end)

  then_("the guided tour is marked complete for me", fn world ->
    # Dismissing pushes an async event to the server, so poll until the
    # completion has round-tripped to the database.
    assert eventually_toured?(world.membership), "tour was never marked complete"
    world
  end)

  # Poll the membership up to ~2s for the completion timestamp to land.
  defp eventually_toured?(membership, attempts \\ 20)
  defp eventually_toured?(_membership, 0), do: false

  defp eventually_toured?(membership, attempts) do
    if Accounts.admin_tour_completed?(Repo.reload(membership)) do
      true
    else
      Process.sleep(100)
      eventually_toured?(membership, attempts - 1)
    end
  end
end
