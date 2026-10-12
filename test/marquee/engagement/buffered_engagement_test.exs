defmodule Marquee.Engagement.BufferedEngagementTest do
  @moduledoc """
  `Engagement.buffer_completion/3` and `Engagement.buffer_drop_off/1` have the
  same call shape as their direct counterparts; the caller cannot tell the
  write is buffered except that rows land on the next buffer flush.
  """

  use Marquee.DataCase, async: false

  alias Marquee.Buffers.EngagementBuffer
  alias Marquee.Engagement
  alias Marquee.Engagement.{PlaybackDropOff, Progress, WatchHistory}

  setup do
    :ok = EngagementBuffer.flush()

    org = insert(:organization)
    viewer = insert(:subscribed_viewer, organization: org)
    video = insert(:video, organization: org, mux_status: "ready", duration: 60.0)
    %{org: org, viewer: viewer, video: video}
  end

  describe "buffer_completion/3" do
    test "returns :ok and lands after flush", %{org: org, viewer: viewer, video: video} do
      assert :ok = Engagement.buffer_completion(org, viewer, video)

      refute Repo.get_by(Progress, viewer_id: viewer.id, video_id: video.id)
      refute Repo.exists?(from h in WatchHistory, where: h.viewer_id == ^viewer.id)

      :ok = EngagementBuffer.flush()

      assert %Progress{completed: true, organization_id: org_id} =
               Repo.get_by(Progress, viewer_id: viewer.id, video_id: video.id)

      assert org_id == org.id
      assert Engagement.get_progress(org, viewer, video).completed

      assert Repo.exists?(
               from h in WatchHistory,
                 where: h.viewer_id == ^viewer.id and h.video_id == ^video.id
             )
    end
  end

  describe "buffer_drop_off/1" do
    test "returns :ok and lands after flush", %{org: org, viewer: viewer, video: video} do
      attrs = %{
        "organization_id" => org.id,
        "viewer_id" => viewer.id,
        "video_id" => video.id,
        "max_position" => 33.0,
        "video_duration" => 60.0
      }

      assert :ok = Engagement.buffer_drop_off(attrs)
      refute Repo.get_by(PlaybackDropOff, viewer_id: viewer.id, video_id: video.id)

      :ok = EngagementBuffer.flush()

      drop = Repo.get_by(PlaybackDropOff, viewer_id: viewer.id, video_id: video.id)
      assert drop.organization_id == org.id
      assert drop.max_position == 33.0
      assert drop.bucket == PlaybackDropOff.bucket_for(33.0)
      assert drop.counted_at == nil
    end

    test "an invalid drop-off still returns :ok and writes nothing", %{org: org, viewer: viewer} do
      assert :ok = Engagement.buffer_drop_off(%{organization_id: org.id, viewer_id: viewer.id})
      assert :ok = EngagementBuffer.flush()
      refute Repo.exists?(from d in PlaybackDropOff, where: d.viewer_id == ^viewer.id)
    end
  end
end
