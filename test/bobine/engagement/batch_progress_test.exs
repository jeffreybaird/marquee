defmodule Bobine.Engagement.BatchProgressTest do
  use Bobine.DataCase, async: true

  alias Bobine.Engagement

  setup do
    org = insert(:organization)
    viewer = insert(:subscribed_viewer, organization: org)

    videos =
      for _i <- 1..3 do
        insert(:video, organization: org, mux_status: "ready", duration: 300.0)
      end

    %{org: org, viewer: viewer, videos: videos}
  end

  describe "batch_get_progress/3" do
    test "returns progress for all requested video IDs", %{
      org: org,
      viewer: viewer,
      videos: [v1, v2, v3]
    } do
      insert(:progress,
        organization: org,
        viewer: viewer,
        video: v1,
        position: 120.0,
        completed: false
      )

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: v2,
        position: 300.0,
        completed: true
      )

      result = Engagement.batch_get_progress(org, viewer, [v1.id, v2.id, v3.id])

      assert Map.has_key?(result, v1.id)
      assert Map.has_key?(result, v2.id)
      assert result[v1.id].position == 120.0
      assert result[v2.id].completed == true
    end

    test "returns empty map when no progress exists", %{org: org, viewer: viewer, videos: videos} do
      video_ids = Enum.map(videos, & &1.id)
      result = Engagement.batch_get_progress(org, viewer, video_ids)

      assert result == %{}
    end

    test "only returns progress for videos in the list", %{
      org: org,
      viewer: viewer,
      videos: [v1, v2, _v3]
    } do
      insert(:progress, organization: org, viewer: viewer, video: v1, position: 50.0)
      insert(:progress, organization: org, viewer: viewer, video: v2, position: 100.0)

      result = Engagement.batch_get_progress(org, viewer, [v1.id])

      assert Map.has_key?(result, v1.id)
      refute Map.has_key?(result, v2.id)
    end

    test "scoped to org + viewer", %{org: org, viewer: viewer, videos: [v1 | _]} do
      other_org = insert(:organization)
      other_viewer = insert(:subscribed_viewer, organization: org)

      insert(:progress, organization: org, viewer: viewer, video: v1, position: 50.0)

      # Different viewer, same org — should not see v1 progress
      assert Engagement.batch_get_progress(org, other_viewer, [v1.id]) == %{}

      # Different org, same viewer ID won't match because org scoping
      assert Engagement.batch_get_progress(other_org, viewer, [v1.id]) == %{}
    end
  end
end
