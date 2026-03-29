defmodule Bobine.Buffers.ProgressBufferTest do
  use Bobine.DataCase, async: false

  alias Bobine.Buffers.ProgressBuffer
  alias Bobine.Engagement.Progress

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

  describe "flush/0" do
    test "flushes buffered records to Postgres" do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)
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
  end
end
