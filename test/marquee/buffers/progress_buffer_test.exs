defmodule Marquee.Buffers.ProgressBufferTest do
  use Marquee.DataCase, async: false

  alias Marquee.Buffers.ProgressBuffer
  alias Marquee.Engagement.Progress

  setup do
    ProgressBuffer.clear()
    :ok
  end

  describe "update/4 and get/3" do
    test "writes to the buffer and reads back" do
      org = insert(:organization)
      user = insert(:user)
      video = insert(:video, organization: org)

      :ok = ProgressBuffer.update(org.id, user.id, video.id, 45.5)

      assert ProgressBuffer.get(org.id, user.id, video.id) == 45.5
    end

    test "multiple updates keep only the latest" do
      org = insert(:organization)
      user = insert(:user)
      video = insert(:video, organization: org)

      :ok = ProgressBuffer.update(org.id, user.id, video.id, 10.0)
      :ok = ProgressBuffer.update(org.id, user.id, video.id, 20.0)
      :ok = ProgressBuffer.update(org.id, user.id, video.id, 30.0)

      assert ProgressBuffer.get(org.id, user.id, video.id) == 30.0
    end
  end

  describe "update_viewer/5 and get_viewer/3" do
    test "writes viewer progress to the buffer and reads it back" do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org)

      :ok = ProgressBuffer.update_viewer(org.id, viewer.id, video.id, 45.5, 120.0)

      assert ProgressBuffer.get_viewer(org.id, viewer.id, video.id) == %{
               position: 45.5,
               duration: 120.0
             }
    end

    test "delete_viewer/3 removes a buffered viewer entry" do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org)

      :ok = ProgressBuffer.update_viewer(org.id, viewer.id, video.id, 10.0, 50.0)
      :ok = ProgressBuffer.delete_viewer(org.id, viewer.id, video.id)

      assert ProgressBuffer.get_viewer(org.id, viewer.id, video.id) == nil
    end
  end

  describe "flush/0" do
    test "flushes buffered records to Postgres" do
      org = insert(:organization)
      user = insert(:user)
      _membership = insert(:membership, organization: org, user: user)
      video = insert(:video, organization: org)

      :ok = ProgressBuffer.update(org.id, user.id, video.id, 55.0)
      :ok = ProgressBuffer.flush()

      progress = Repo.get_by(Progress, user_id: user.id, video_id: video.id)
      assert progress != nil
      assert progress.position == 55.0
    end

    test "clears buffer after flush" do
      org = insert(:organization)
      user = insert(:user)
      video = insert(:video, organization: org)

      :ok = ProgressBuffer.update(org.id, user.id, video.id, 10.0)
      :ok = ProgressBuffer.flush()

      assert ProgressBuffer.get(org.id, user.id, video.id) == nil
    end

    test "flushes buffered viewer records to Postgres" do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org)

      :ok = ProgressBuffer.update_viewer(org.id, viewer.id, video.id, 33.0, 80.0)
      :ok = ProgressBuffer.flush()

      progress = Repo.get_by(Progress, viewer_id: viewer.id, video_id: video.id)
      assert progress != nil
      assert progress.position == 33.0
      assert progress.duration == 80.0
    end

    test "flush resets completed to false when new viewer progress is buffered" do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org)

      # Simulate a previously completed video
      insert(:progress,
        organization: org,
        viewer: viewer,
        video: video,
        position: 120.0,
        duration: 120.0,
        completed: true
      )

      # Viewer starts rewatching — new progress goes to buffer
      :ok = ProgressBuffer.update_viewer(org.id, viewer.id, video.id, 15.0, 120.0)
      :ok = ProgressBuffer.flush()

      progress = Repo.get_by(Progress, viewer_id: viewer.id, video_id: video.id)
      assert progress.position == 15.0
      assert progress.completed == false
    end

    test "flush resets completed to false when new user progress is buffered" do
      org = insert(:organization)
      user = insert(:user)
      _membership = insert(:membership, organization: org, user: user)
      video = insert(:video, organization: org)

      # Simulate a previously completed video
      insert(:progress,
        organization: org,
        user: user,
        video: video,
        position: 60.0,
        completed: true
      )

      # User starts rewatching — new progress goes to buffer
      :ok = ProgressBuffer.update(org.id, user.id, video.id, 5.0)
      :ok = ProgressBuffer.flush()

      progress = Repo.get_by(Progress, user_id: user.id, video_id: video.id)
      assert progress.position == 5.0
      assert progress.completed == false
    end
  end
end
