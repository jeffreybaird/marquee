defmodule Bobine.Engagement.ContinueWatchingTest do
  use Bobine.DataCase, async: true

  alias Bobine.Accounts.Scope
  alias Bobine.Content
  alias Bobine.Engagement

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    viewer = insert(:subscribed_viewer, organization: org)

    %{org: org, scope: scope, viewer: viewer}
  end

  defp build_series_with_seasons(scope, opts) do
    title = Keyword.get(opts, :title, "Series")
    season_count = Keyword.get(opts, :seasons, 1)
    episodes_per_season = Keyword.get(opts, :episodes, 3)

    {:ok, series} = Content.create_series(scope, %{title: title})

    seasons =
      for n <- 1..season_count do
        {:ok, season} =
          Content.create_season(scope, series, %{
            title: "Season #{n}",
            season_number: n
          })

        episodes =
          for ep_n <- 1..episodes_per_season do
            video =
              insert(:video,
                organization: scope.organization,
                title: "#{title} S#{n}E#{ep_n}",
                mux_status: "ready",
                duration: 1800.0
              )

            {:ok, episode} = Content.add_episode(scope, season, video, %{episode_number: ep_n})
            %{episode: episode, video: video}
          end

        %{season: season, episodes: episodes}
      end

    {series, seasons}
  end

  defp insert_progress(org, viewer, video, position, completed) do
    insert(:progress,
      organization: org,
      viewer: viewer,
      video: video,
      position: position,
      duration: video.duration || 1800.0,
      completed: completed
    )
  end

  ## -----------------------------------------------------------------------
  ## In-progress episode
  ## -----------------------------------------------------------------------

  describe "in-progress episode" do
    test "episode with progress appears as :in_progress with episode_context",
         %{org: org, scope: scope, viewer: viewer} do
      {_series, [%{episodes: [%{video: v1} | _]}]} =
        build_series_with_seasons(scope, title: "Show", episodes: 3)

      insert_progress(org, viewer, v1, 600.0, false)

      %{results: [item]} = Engagement.list_continue_watching(org, viewer)

      assert item.type == :in_progress
      assert item.video.id == v1.id
      assert item.episode_context.series.title == "Show"
      assert item.episode_context.season_number == 1
      assert item.episode_context.episode_number == 1
      assert item.position == 600.0
      assert item.duration == 1800.0
    end

    test "standalone in-progress video is unchanged", %{org: org, viewer: viewer} do
      video = insert(:video, organization: org, title: "Solo", duration: 600.0)
      insert_progress(org, viewer, video, 100.0, false)

      %{results: [item]} = Engagement.list_continue_watching(org, viewer)

      assert item.type == :in_progress
      assert item.episode_context == nil
      assert item.series_id == nil
      assert item.video.id == video.id
    end
  end

  ## -----------------------------------------------------------------------
  ## Between-episodes
  ## -----------------------------------------------------------------------

  describe "between episodes" do
    test "completed E1 surfaces E2 as :between_episodes",
         %{org: org, scope: scope, viewer: viewer} do
      {_series, [%{episodes: [%{video: v1}, %{video: v2} | _]}]} =
        build_series_with_seasons(scope, title: "Show", episodes: 3)

      insert_progress(org, viewer, v1, 1800.0, true)

      %{results: [item]} = Engagement.list_continue_watching(org, viewer)

      assert item.type == :between_episodes
      assert item.video.id == v2.id
      assert item.position == 0.0
      assert item.episode_context.episode_number == 2
    end

    test "between item is suppressed when next episode already in progress",
         %{org: org, scope: scope, viewer: viewer} do
      {_series, [%{episodes: [%{video: v1}, %{video: v2} | _]}]} =
        build_series_with_seasons(scope, title: "Show", episodes: 3)

      insert_progress(org, viewer, v1, 1800.0, true)
      insert_progress(org, viewer, v2, 200.0, false)

      %{results: [item]} = Engagement.list_continue_watching(org, viewer)

      # Only one item should appear (the in-progress v2), not two
      assert item.type == :in_progress
      assert item.video.id == v2.id
    end

    test "no between item when on the last episode", %{org: org, scope: scope, viewer: viewer} do
      {_series, [%{episodes: episodes}]} =
        build_series_with_seasons(scope, title: "Show", episodes: 3)

      [_e1, _e2, %{video: last}] = episodes
      insert_progress(org, viewer, last, 1800.0, true)

      %{results: results} = Engagement.list_continue_watching(org, viewer)
      # Only season 1 exists; nothing should appear
      assert results == []
    end
  end

  ## -----------------------------------------------------------------------
  ## Next season
  ## -----------------------------------------------------------------------

  describe "next season" do
    test "completing all of S1 surfaces S2 as :next_season",
         %{org: org, scope: scope, viewer: viewer} do
      {_series, [%{episodes: s1_eps}, %{season: s2}]} =
        build_series_with_seasons(scope, title: "Show", seasons: 2, episodes: 2)

      Enum.each(s1_eps, fn %{video: v} ->
        insert_progress(org, viewer, v, 1800.0, true)
      end)

      %{results: [item]} = Engagement.list_continue_watching(org, viewer)

      assert item.type == :next_season
      assert item.season.id == s2.id
      assert item.video == nil
    end

    test "completed series with no further season is excluded",
         %{org: org, scope: scope, viewer: viewer} do
      {_series, [%{episodes: s1_eps}]} =
        build_series_with_seasons(scope, title: "Done", seasons: 1, episodes: 2)

      Enum.each(s1_eps, fn %{video: v} ->
        insert_progress(org, viewer, v, 1800.0, true)
      end)

      %{results: results} = Engagement.list_continue_watching(org, viewer)
      assert results == []
    end

    test "next-season item is suppressed when viewer already started S2",
         %{org: org, scope: scope, viewer: viewer} do
      {_series, [%{episodes: s1_eps}, %{episodes: [%{video: s2_v1} | _]}]} =
        build_series_with_seasons(scope, title: "Show", seasons: 2, episodes: 2)

      Enum.each(s1_eps, fn %{video: v} ->
        insert_progress(org, viewer, v, 1800.0, true)
      end)

      insert_progress(org, viewer, s2_v1, 100.0, false)

      %{results: [item]} = Engagement.list_continue_watching(org, viewer)
      # Should be the in-progress S2 episode, not a :next_season card
      assert item.type == :in_progress
      assert item.video.id == s2_v1.id
    end
  end

  ## -----------------------------------------------------------------------
  ## Deduplication
  ## -----------------------------------------------------------------------

  describe "deduplication" do
    test "two in-progress episodes from the same series collapse to one",
         %{org: org, scope: scope, viewer: viewer} do
      {_series, [%{episodes: [%{video: v1}, %{video: v2} | _]}]} =
        build_series_with_seasons(scope, title: "Show", episodes: 3)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: v1,
        position: 100.0,
        duration: 1800.0,
        completed: false,
        updated_at: DateTime.add(now, -120, :second)
      )

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: v2,
        position: 50.0,
        duration: 1800.0,
        completed: false,
        updated_at: now
      )

      %{results: results} = Engagement.list_continue_watching(org, viewer)
      assert length(results) == 1
      assert hd(results).video.id == v2.id
    end

    test "standalone videos are never deduplicated", %{org: org, viewer: viewer} do
      v1 = insert(:video, organization: org, duration: 600.0)
      v2 = insert(:video, organization: org, duration: 600.0)

      insert_progress(org, viewer, v1, 100.0, false)
      insert_progress(org, viewer, v2, 200.0, false)

      %{results: results} = Engagement.list_continue_watching(org, viewer)
      assert length(results) == 2
    end
  end

  ## -----------------------------------------------------------------------
  ## Multi-tenant
  ## -----------------------------------------------------------------------

  describe "multi-tenant isolation" do
    test "episodes from another org are not surfaced", %{viewer: viewer, org: org} do
      other_org = insert(:organization)
      other_user = insert(:user)
      other_mem = insert(:membership, organization: other_org, user: other_user, role: :editor)
      other_scope = Scope.for_user(other_user) |> Scope.with_organization(other_org, other_mem)

      {_series, [%{episodes: [%{video: v1} | _]}]} =
        build_series_with_seasons(other_scope, title: "Other", episodes: 2)

      # Foreign-org viewer with their own progress on the foreign video
      foreign_viewer = insert(:subscribed_viewer, organization: other_org)
      insert_progress(other_org, foreign_viewer, v1, 100.0, false)

      %{results: results} = Engagement.list_continue_watching(org, viewer)
      assert results == []
    end
  end
end
