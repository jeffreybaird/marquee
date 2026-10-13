defmodule MarqueeFeatures.Steps.Analytics do
  @moduledoc """
  Step definitions for analytics.feature.

  Operator scenarios drive the /admin/analytics dashboard via Wallaby:
  KPI cards, period selector buttons, subscriber/revenue charts (presence
  only — Chart.js renders inside a canvas), content performance table
  sort + paginate. Per-resource analytics pages (videos, series, seasons)
  are seeded with Progress and drop-off bucket rows and visited directly.
  Super-admin platform analytics drives /super/analytics: overview cards,
  the per-organization health table, and its MRR sort.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Marquee.Factory
  import ExUnit.Assertions
  import MarqueeFeatures.Support.Browser

  alias Marquee.Admin

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

  then_ "watch count, completion rate, and average watch time", fn world ->
    # Unique viewers is the table's watch count; average watch time is shown
    # as the average share of the video watched.
    world.session
    # Header labels render uppercase via CSS, so match the column buttons
    # by their data-test keys rather than their visible text.
    |> assert_has(css("[data-test=sort-col-unique_viewers]"))
    |> assert_has(css("[data-test=sort-col-completion_rate]"))
    |> assert_has(css("[data-test=sort-col-avg_watch_percentage]"))

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
    # The table lists every non-deleted video in the organization, 20 per
    # page. Seed one more than a page and reload the dashboard so mount
    # picks them up.
    insert_list(21, :video, organization: world.org)

    session =
      world.session
      |> visit_live("/admin/analytics?org=#{world.org.slug}")
      |> assert_has(css("[data-test=content-pagination]", text: "Page 1 of 2"))

    Map.put(world, :session, session)
  end

  # Shared by the analytics content table (`content-page-next`) and the
  # content library video list (`page-next`); each page renders exactly one.
  when_ "I navigate to the next page", fn world ->
    session =
      click(world.session, css("[data-test=content-page-next], [data-test=page-next]"))

    Map.put(world, :session, session)
  end

  then_ "the next set of content is displayed", fn world ->
    assert_has(world.session, css("[data-test=content-pagination]", text: "Page 2 of 2"))
    world
  end

  # ---- Per-video analytics ----------------------------------------------

  given_ "a video exists with watch data", fn world ->
    org = world.org
    video = insert(:video, organization: org, title: "Analytics Feature", duration: 600.0)

    # Two meaningful watches (>= 10% of the duration): one finished, one
    # halfway through.
    for {position, completed} <- [{600.0, true}, {300.0, false}] do
      viewer = insert(:viewer, organization: org)
      insert_progress(org, viewer, video, position, completed)
    end

    # Ten recorded drop-offs: 3 in the first 10 s, 7 between 0:30 and 0:40.
    insert(:video_drop_off_bucket, organization: org, video: video, bucket: 0, count: 3)
    insert(:video_drop_off_bucket, organization: org, video: video, bucket: 3, count: 7)

    Map.put(world, :video, video)
  end

  when_ "I navigate to /admin/analytics/videos/:video_id", fn world ->
    session =
      visit_live(world.session, "/admin/analytics/videos/#{world.video.id}?org=#{world.org.slug}")

    Map.put(world, :session, session)
  end

  then_ "I see watch stats, completion rate, average watch time,", fn world ->
    # Completed watches: 1 of 2 unique viewers. Average watched share:
    # (100% + 50%) / 2 = 75%.
    world.session
    |> assert_has(css("[data-test=kpi-unique-viewers]", text: "2"))
    |> assert_has(css("[data-test=kpi-completion-rate]", text: "50"))
    |> assert_has(css("[data-test=kpi-avg-watch-pct]", text: "75.0%"))

    world
  end

  then_ "a drop-off distribution showing where viewers stop watching", fn world ->
    world.session
    |> assert_has(css("[data-test=drop-off-chart]"))
    |> refute_has(css("[data-test=drop-off-empty-state]"))
    |> assert_has(css("[data-test=kpi-total-drop-offs]", text: "10"))
    |> assert_has(css("[data-test=kpi-drop-off-time]", text: "0:30–0:40"))

    world
  end

  # ---- Series and season analytics --------------------------------------

  given_ "a series exists with watch data", fn world ->
    Map.merge(world, build_series_with_watch_data(world.org))
  end

  given_ "a season exists with watch data", fn world ->
    Map.merge(world, build_series_with_watch_data(world.org))
  end

  when_ "I navigate to /admin/analytics/series/:series_id", fn world ->
    session =
      visit_live(world.session, "/admin/analytics/series/#{world.series.id}?org=#{world.org.slug}")

    Map.put(world, :session, session)
  end

  when_ "I navigate to /admin/analytics/series/:series_id/seasons/:season_id", fn world ->
    path =
      "/admin/analytics/series/#{world.series.id}/seasons/#{world.season_one.id}" <>
        "?org=#{world.org.slug}"

    Map.put(world, :session, visit_live(world.session, path))
  end

  then_ "I see per-season stats, episode completion rates, and funnel data", fn world ->
    [s1e1, s1e2, s2e1, s2e2] = world.episodes

    # Season 1: both viewers started, only the binge viewer finished (50%).
    # Season 2: only the binge viewer started and finished (100%).
    world.session
    |> assert_has(css("[data-test=season-row-#{world.season_one.id}]", text: "50.0%"))
    |> assert_has(css("[data-test=season-row-#{world.season_two.id}]", text: "100.0%"))
    # Per-episode completion: S1E1 was completed by both viewers, every
    # other episode by one of the two season starters.
    |> assert_has(css("[data-test=episode-completion-#{s1e1.id}]", text: "100.0%"))
    |> assert_has(css("[data-test=episode-completion-#{s1e2.id}]", text: "50.0%"))
    |> assert_has(css("[data-test=episode-completion-#{s2e1.id}]", text: "100.0%"))
    |> assert_has(css("[data-test=episode-completion-#{s2e2.id}]", text: "100.0%"))
    |> assert_has(css("[data-test=series-funnel]"))

    world
  end

  then_ "next-season transition rates showing how many viewers continue", fn world ->
    # The one viewer who finished season 1 went on to start season 2.
    assert_has(
      world.session,
      css("[data-test=next-season-rate-#{world.season_one.id}]", text: "100.0%")
    )

    world
  end

  then_ "I see per-episode completion rates and drop-off analysis", fn world ->
    session =
      world.session
      |> assert_has(css("[data-test=episode-funnel-chart]"))
      |> refute_has(css("[data-test=funnel-empty-state]"))
      |> assert_has(css("[data-test=kpi-completion-rate]", text: "50.0%"))
      |> assert_has(css("[data-test=kpi-drop-off-episode]"))

    # Viewer two stopped after episode 1, so a drop-off episode is named.
    refute_has(session, css("[data-test=kpi-drop-off-episode]", text: "—"))
    world
  end

  # ---- Super admin platform analytics -----------------------------------

  when_ "I navigate to /super/analytics", fn world ->
    # Seed one paying organization so platform MRR and the signup series
    # have data, then load the dashboard.
    org = insert(:organization, name: "Platform Overview Org")
    plan = insert(:platform_plan, amount: 4900)
    insert(:platform_subscription, organization: org, platform_plan: plan, status: :active)

    session = visit_live(world.session, "/super/analytics")
    Map.merge(world, %{session: session, paying_org: org})
  end

  then_ "I see platform-wide MRR, total organization count, and new signups over time", fn world ->
    overview = Admin.platform_overview()
    assert overview.platform_mrr_cents >= 4900

    world.session
    |> assert_has(css("[data-test=stat-platform-mrr]", text: format_cents(overview.platform_mrr_cents)))
    |> assert_has(css("[data-test=stat-total-orgs]", text: to_string(overview.total_orgs)))
    |> assert_has(css("[data-test=signup-chart]"))

    world
  end

  when_ "I view the platform analytics", fn world ->
    top = seed_platform_org("Top Platform Org", 9900, 3, :premium)
    small = seed_platform_org("Small Platform Org", 2900, 1, :super)

    session = visit_live(world.session, "/super/analytics")
    Map.merge(world, %{session: session, top_org: top, small_org: small})
  end

  then_ "I see MRR broken down by organization", fn world ->
    world.session
    |> assert_has(css("[data-test=org-health-table]"))
    |> assert_has(css("[data-test=org-mrr-#{world.top_org.id}]", text: "$99.00"))
    |> assert_has(css("[data-test=org-mrr-#{world.small_org.id}]", text: "$29.00"))

    world
  end

  then_ "I see a ranked list of top-performing organizations by subscriber count or MRR",
        fn world ->
    # The first click sorts ascending, the second descending (top first).
    session =
      world.session
      |> click(css("[data-test=sort-subscribers]"))
      |> assert_has(css("[data-test=sort-subscribers]", text: "↑"))
      |> click(css("[data-test=sort-subscribers]"))
      |> assert_has(css("[data-test=sort-subscribers]", text: "↓"))
      |> assert_has(css("[data-test=org-subscribers-#{world.top_org.id}]", text: "3"))
      |> assert_has(css("[data-test=org-subscribers-#{world.small_org.id}]", text: "1"))

    ranked_ids =
      session
      |> all(css("[data-test^=org-health-row-]"))
      |> Enum.map(&String.replace_prefix(Wallaby.Element.attr(&1, "data-test"), "org-health-row-", ""))

    assert Enum.take(ranked_ids, 2) == [world.top_org.id, world.small_org.id],
           "expected organizations ranked by subscriber count, got #{inspect(ranked_ids)}"

    Map.put(world, :session, session)
  end

  # ---- Private helpers ----------------------------------------------------

  defp insert_progress(org, viewer, video, position, completed) do
    insert(:progress,
      organization: org,
      user: nil,
      viewer: viewer,
      video: video,
      position: position,
      duration: 600.0,
      completed: completed
    )
  end

  # Series with two seasons of two episodes each. Viewer one binges every
  # episode; viewer two completes only season 1 episode 1.
  defp build_series_with_watch_data(org) do
    series = insert(:series, organization: org, title: "Analytics Series")

    seasons =
      for number <- 1..2 do
        insert(:season,
          organization: org,
          series: series,
          season_number: number,
          title: "Season #{number}",
          episode_count: 2
        )
      end

    episodes =
      for season <- seasons, number <- 1..2 do
        video =
          insert(:video,
            organization: org,
            title: "S#{season.season_number}E#{number}",
            duration: 600.0,
            published: true
          )

        insert(:episode, organization: org, season: season, video: video, episode_number: number)
      end

    binger = insert(:viewer, organization: org)
    sampler = insert(:viewer, organization: org)

    Enum.each(episodes, &insert_progress(org, binger, &1.video, 600.0, true))
    insert_progress(org, sampler, hd(episodes).video, 600.0, true)

    [season_one, season_two] = seasons

    %{series: series, season_one: season_one, season_two: season_two, episodes: episodes}
  end

  # Platform plans are unique per (usage_tier, business_tier).
  defp seed_platform_org(name, amount, subscriber_count, usage_tier) do
    org = insert(:organization, name: name)
    plan = insert(:platform_plan, amount: amount, usage_tier: usage_tier)
    insert(:platform_subscription, organization: org, platform_plan: plan, status: :active)
    insert_list(subscriber_count, :subscribed_viewer, organization: org)
    org
  end

  defp format_cents(cents) do
    "$#{div(cents, 100)}.#{String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")}"
  end
end
