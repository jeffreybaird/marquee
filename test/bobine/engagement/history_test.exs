defmodule Bobine.Engagement.HistoryTest do
  use Bobine.DataCase, async: true

  alias Bobine.Engagement

  setup do
    org = insert(:organization)
    viewer = insert(:subscribed_viewer, organization: org)
    video = insert(:video, organization: org, mux_status: "ready", duration: 100.0)

    %{org: org, viewer: viewer, video: video}
  end

  describe "record_watch_activity/3" do
    test "creates a history entry", %{org: org, viewer: viewer, video: video} do
      assert {:ok, entry} = Engagement.record_watch_activity(org, viewer, video)
      assert entry.viewer_id == viewer.id
      assert entry.video_id == video.id
    end

    test "updates existing recent entry instead of creating duplicate", %{org: org, viewer: viewer, video: video} do
      {:ok, entry1} = Engagement.record_watch_activity(org, viewer, video)
      {:ok, entry2} = Engagement.record_watch_activity(org, viewer, video)

      # Should update the same entry
      assert entry1.id == entry2.id
    end
  end

  describe "list_watch_history/3" do
    test "returns most recent first", %{org: org, viewer: viewer} do
      v1 = insert(:video, organization: org)
      v2 = insert(:video, organization: org)

      insert(:watch_history,
        organization: org,
        viewer: viewer,
        video: v1,
        watched_at: ~U[2026-01-01 10:00:00Z]
      )

      insert(:watch_history,
        organization: org,
        viewer: viewer,
        video: v2,
        watched_at: ~U[2026-01-02 10:00:00Z]
      )

      result = Engagement.list_watch_history(org, viewer)
      ids = Enum.map(result.results, & &1.video_id)
      assert ids == [v2.id, v1.id]
    end
  end

  describe "list_continue_watching/3" do
    test "returns in-progress videos only", %{org: org, viewer: viewer} do
      v1 = insert(:video, organization: org)
      v2 = insert(:video, organization: org)

      insert(:progress, organization: org, viewer: viewer, video: v1, position: 50.0, completed: false)
      insert(:progress, organization: org, viewer: viewer, video: v2, position: 0.0, completed: false)

      result = Engagement.list_continue_watching(org, viewer)
      # Only v1 has position > 0
      assert result.total == 1
      assert hd(result.results).video_id == v1.id
    end

    test "excludes completed videos", %{org: org, viewer: viewer} do
      v1 = insert(:video, organization: org)
      v2 = insert(:video, organization: org)

      insert(:progress, organization: org, viewer: viewer, video: v1, position: 50.0, completed: false)
      insert(:progress, organization: org, viewer: viewer, video: v2, position: 90.0, completed: true)

      result = Engagement.list_continue_watching(org, viewer)
      assert result.total == 1
      assert hd(result.results).video_id == v1.id
    end
  end

  describe "mark_completed/3" do
    test "sets completed flag on progress", %{org: org, viewer: viewer, video: video} do
      insert(:progress, organization: org, viewer: viewer, video: video, position: 99.0, completed: false)

      :ok = Engagement.mark_completed(org, viewer, video)

      progress = Engagement.get_progress(org, viewer, video)
      assert progress.completed == true
    end

    test "creates progress record if none exists", %{org: org, viewer: viewer, video: video} do
      :ok = Engagement.mark_completed(org, viewer, video)

      progress = Engagement.get_progress(org, viewer, video)
      assert progress != nil
      assert progress.completed == true
    end
  end
end
