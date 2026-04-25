defmodule Bobine.Engagement.ContinueWatchingDismissalTest do
  use Bobine.DataCase, async: true

  alias Bobine.Accounts.Scope
  alias Bobine.Content
  alias Bobine.Engagement

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    viewer = insert(:viewer, organization: org)

    %{org: org, scope: scope, viewer: viewer}
  end

  defp insert_progress(org, viewer, video, position, completed, opts \\ []) do
    attrs = [
      organization: org,
      viewer: viewer,
      video: video,
      position: position,
      duration: video.duration || 1800.0,
      completed: completed
    ]

    insert(:progress, attrs ++ opts)
  end

  defp build_video(org, opts \\ []) do
    insert(:video, [organization: org, mux_status: "ready", duration: 1800.0] ++ opts)
  end

  ## -----------------------------------------------------------------------
  ## dismiss_continue_watching/3 — standalone video
  ## -----------------------------------------------------------------------

  describe "dismiss_continue_watching/3 — video" do
    test "dismisses a standalone video", %{org: org, viewer: viewer} do
      video = build_video(org)
      insert_progress(org, viewer, video, 300.0, false)

      assert {:ok, _dismissal} =
               Engagement.dismiss_continue_watching(org, viewer, %{video_id: video.id})
    end

    test "dismissed video disappears from continue watching", %{org: org, viewer: viewer} do
      video = build_video(org)
      insert_progress(org, viewer, video, 300.0, false)

      {:ok, _} = Engagement.dismiss_continue_watching(org, viewer, %{video_id: video.id})

      assert %{results: []} = Engagement.list_continue_watching(org, viewer)
    end

    test "re-dismissing a video upserts the dismissal timestamp", %{org: org, viewer: viewer} do
      video = build_video(org)
      insert_progress(org, viewer, video, 300.0, false)

      {:ok, _} = Engagement.dismiss_continue_watching(org, viewer, %{video_id: video.id})
      assert {:ok, _} = Engagement.dismiss_continue_watching(org, viewer, %{video_id: video.id})
    end

    test "dismissed video resurfaces after viewer watches again", %{org: org, viewer: viewer} do
      video = build_video(org)

      progress =
        insert_progress(org, viewer, video, 300.0, false,
          inserted_at: ~U[2024-01-01 10:00:00Z],
          updated_at: ~U[2024-01-01 10:00:00Z]
        )

      dismissed_at = ~U[2024-01-01 11:00:00Z]

      insert(:continue_watching_dismissal,
        organization: org,
        viewer: viewer,
        video: video,
        series: nil,
        dismissed_at: dismissed_at
      )

      assert %{results: []} = Engagement.list_continue_watching(org, viewer)

      # Simulate watching again: progress updated_at advances past dismissed_at.
      # Repo.update to bypass buffer
      progress
      |> Ecto.Changeset.change(position: 600.0, updated_at: ~U[2024-01-01 12:00:00Z])
      |> Bobine.Repo.update!()

      assert %{results: [item]} = Engagement.list_continue_watching(org, viewer)
      assert item.video.id == video.id
    end

    test "multi-tenant: dismissal from org A does not hide item for org B viewer", %{
      org: org,
      viewer: viewer
    } do
      other_org = insert(:organization)
      other_viewer = insert(:viewer, organization: other_org)
      video = build_video(org)
      other_video = insert(:video, organization: other_org, mux_status: "ready", duration: 1800.0)

      insert_progress(org, viewer, video, 300.0, false)
      insert_progress(other_org, other_viewer, other_video, 300.0, false)

      {:ok, _} = Engagement.dismiss_continue_watching(org, viewer, %{video_id: video.id})

      assert %{results: [item]} = Engagement.list_continue_watching(other_org, other_viewer)
      assert item.video.id == other_video.id
    end
  end

  ## -----------------------------------------------------------------------
  ## dismiss_continue_watching/3 — series
  ## -----------------------------------------------------------------------

  describe "dismiss_continue_watching/3 — series" do
    test "dismisses a series card", %{org: org, scope: scope, viewer: viewer} do
      {:ok, series} = Content.create_series(scope, %{title: "Show"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      video = build_video(org, title: "Show S1E1")
      {:ok, _ep} = Content.add_episode(scope, season, video, %{episode_number: 1})
      insert_progress(org, viewer, video, 300.0, false)

      assert {:ok, _dismissal} =
               Engagement.dismiss_continue_watching(org, viewer, %{series_id: series.id})
    end

    test "dismissed series disappears from continue watching", %{
      org: org,
      scope: scope,
      viewer: viewer
    } do
      {:ok, series} = Content.create_series(scope, %{title: "Show"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      video = build_video(org, title: "Show S1E1")
      {:ok, _ep} = Content.add_episode(scope, season, video, %{episode_number: 1})
      insert_progress(org, viewer, video, 300.0, false)

      {:ok, _} = Engagement.dismiss_continue_watching(org, viewer, %{series_id: series.id})

      assert %{results: []} = Engagement.list_continue_watching(org, viewer)
    end

    test "dismissed between_episodes item resurfaces when viewer watches next episode",
         %{org: org, scope: scope, viewer: viewer} do
      {:ok, series} = Content.create_series(scope, %{title: "Show"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      v1 = build_video(org, title: "Show S1E1")
      v2 = build_video(org, title: "Show S1E2")
      {:ok, _ep1} = Content.add_episode(scope, season, v1, %{episode_number: 1})
      {:ok, _ep2} = Content.add_episode(scope, season, v2, %{episode_number: 2})

      # ep1 completed → between_episodes item surfaced
      ep1_progress =
        insert_progress(org, viewer, v1, 1800.0, true,
          inserted_at: ~U[2024-01-01 10:00:00Z],
          updated_at: ~U[2024-01-01 10:00:00Z]
        )

      dismissed_at = ~U[2024-01-01 11:00:00Z]

      insert(:continue_watching_dismissal,
        organization: org,
        viewer: viewer,
        video: nil,
        series: series,
        dismissed_at: dismissed_at
      )

      assert %{results: []} = Engagement.list_continue_watching(org, viewer)

      # Viewer starts ep2 — progress.updated_at > dismissed_at → resurface
      ep1_progress
      |> Ecto.Changeset.change(updated_at: ~U[2024-01-01 12:00:00Z])
      |> Bobine.Repo.update!()

      assert %{results: [_item]} = Engagement.list_continue_watching(org, viewer)
    end
  end
end
