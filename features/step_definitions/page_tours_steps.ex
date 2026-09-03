defmodule MarqueeFeatures.Steps.PageTours do
  @moduledoc """
  Step definitions for page_tours.feature.

  Per-page tours are Shepherd.js walkthroughs that auto-launch the first time an
  operator visits a page. Completion is recorded per user, per organization, per
  page key (`page_tour_completions`), so each page's tour is independent. Login
  and page navigation are shared steps.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import ExUnit.Assertions

  alias Marquee.Accounts

  @content_page "content"

  # ---- Setup --------------------------------------------------------------

  given_("I have already seen the content page tour", fn world ->
    {:ok, _} = Accounts.complete_page_tour(world.operator, world.org, @content_page)
    world
  end)

  # ---- Actions ------------------------------------------------------------

  when_("I dismiss the page tour", fn world ->
    session = click(world.session, css(".shepherd-cancel-icon"))
    Map.put(world, :session, session)
  end)

  when_("I click the page tour link", fn world ->
    session = click(world.session, css("[data-test=restart-page-tour]"))
    Map.put(world, :session, session)
  end)

  # ---- Assertions ---------------------------------------------------------

  then_("I am greeted by the content page tour", fn world ->
    assert_has(world.session, css(".shepherd-element", text: "content library"))
    world
  end)

  then_("the content page tour does not launch", fn world ->
    refute_has(world.session, css(".shepherd-element"))
    world
  end)

  then_("I do not see the page tour link", fn world ->
    refute_has(world.session, css("[data-test=restart-page-tour]"))
    world
  end)

  then_("the content page tour is marked seen for me", fn world ->
    # Dismissing pushes an async event to the server, so poll until the
    # completion has round-tripped to the database.
    assert eventually_seen?(world.operator, world.org),
           "content page tour was never marked seen"

    world
  end)

  # Poll up to ~2s for the completion to land.
  defp eventually_seen?(user, org, attempts \\ 20)
  defp eventually_seen?(_user, _org, 0), do: false

  defp eventually_seen?(user, org, attempts) do
    if Accounts.page_tour_completed?(user, org, @content_page) do
      true
    else
      Process.sleep(100)
      eventually_seen?(user, org, attempts - 1)
    end
  end
end
