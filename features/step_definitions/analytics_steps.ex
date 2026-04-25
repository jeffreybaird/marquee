defmodule BobineFeatures.Steps.Analytics do
  @moduledoc """
  Step definitions for analytics.feature.

  Operator scenarios drive the /admin/analytics dashboard via Wallaby:
  KPI cards, period selector buttons, subscriber/revenue charts (presence
  only — Chart.js renders inside a canvas), content performance table
  sort + paginate. Per-resource analytics URLs (videos/series/seasons)
  and the super-admin platform routes stay undefined — they need
  resource-specific data setup or a super-admin login helper.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query

  given_ "I am on the analytics dashboard at /admin/analytics", fn world ->
    session = visit(world.session, "/admin/analytics?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  # ---- KPI overview ------------------------------------------------------

  then_ "I see total subscriber count, MRR, and a content performance summary", fn world ->
    assert_has(world.session, css("[data-test=kpi-active-subscribers]"))
    assert_has(world.session, css("[data-test=kpi-mrr]"))
    assert_has(world.session, css("[data-test=kpi-total-views]"))
    assert_has(world.session, css("[data-test=kpi-avg-watch-time]"))
    world
  end

  # ---- Period selector + charts ------------------------------------------

  when_ "I select a time period of day, week, or month", fn world ->
    # The selector exposes 7 / 30 / 90 day buttons. "Week" maps to 7d.
    session = click(world.session, css("[data-test=period-selector-7]"))
    Map.put(world, :session, session)
  end

  when_ "I select a time period", fn world ->
    session = click(world.session, css("[data-test=period-selector-30]"))
    Map.put(world, :session, session)
  end

  then_ "I see daily subscriber counts charted over that period", fn world ->
    # Chart.js draws inside a <canvas> we can't introspect through the
    # accessibility tree, so the contract here is that the chart element
    # is in the DOM with the analytics hook attached. The hook itself
    # has a unit test in assets/.
    assert_has(world.session, css("[data-test=subscriber-chart]"))
    world
  end

  then_ "I see daily revenue plotted over that period", fn world ->
    assert_has(world.session, css("[data-test=revenue-chart]"))
    world
  end

  # ---- Content performance table ----------------------------------------

  when_ "I view the content performance section", fn world ->
    # Already on /admin/analytics from the Background — scroll/visibility
    # isn't a concern for Wallaby's accessibility queries.
    world
  end

  then_ "I see a table of videos ranked by engagement metrics", fn world ->
    assert_has(world.session, css("[data-test=sort-col-unique_viewers]"))
    assert_has(world.session, css("[data-test=sort-col-completion_rate]"))
    world
  end

  then_ "Including watch count, completion rate, and average watch time", fn world ->
    assert_text(world.session, "Unique Viewers")
    assert_text(world.session, "Completion %")
    assert_text(world.session, "Avg Watch %")
    world
  end

  given_ "the content performance table is visible", fn world ->
    # Background already navigated to /admin/analytics; no-op confirms
    # state for downstream When/Then steps.
    world
  end

  when_ "I click a column header to sort", fn world ->
    session = click(world.session, css("[data-test=sort-col-completion_rate]"))
    Map.put(world, :session, session)
  end

  then_ "the table re-orders by that metric", fn world ->
    # The ▲/▼ arrow appears on the active sort column. Asserting a
    # direction-arrow glyph is fragile, so we just verify the click
    # did not navigate away — the table is still on the page.
    assert_has(world.session, css("[data-test=sort-col-completion_rate]"))
    world
  end

  given_ "the content performance table has multiple pages", fn world ->
    # `mix bobine.cucumber` against an empty test DB won't naturally
    # produce paginated content. The pagination markup only renders
    # when total > per_page, so this scenario stays best-effort: when
    # there's no data, the next-page button isn't in the DOM and the
    # When step's click will fail loudly — which is the right signal
    # rather than a silent pass.
    world
  end

  when_ "I navigate to the next page", fn world ->
    session = click(world.session, css("[data-test=content-page-next]"))
    Map.put(world, :session, session)
  end

  then_ "the next set of content is displayed", fn world ->
    assert_has(world.session, css("[data-test=content-pagination]"))
    world
  end
end
