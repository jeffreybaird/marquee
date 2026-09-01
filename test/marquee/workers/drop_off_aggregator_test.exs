defmodule Marquee.Workers.DropOffAggregatorTest do
  use Marquee.DataCase, async: true
  use Oban.Testing, repo: Marquee.Repo

  alias Marquee.Engagement.{PlaybackDropOff, VideoDropOffBucket}
  alias Marquee.Workers.DropOffAggregator

  defp aged(seconds_ago) do
    DateTime.add(DateTime.utc_now(), -seconds_ago, :second) |> DateTime.truncate(:second)
  end

  defp insert_drop_off(attrs) do
    insert(
      :playback_drop_off,
      Map.to_list(Map.merge(%{counted_at: nil, outcome: nil}, attrs))
    )
  end

  defp run_worker do
    assert :ok = perform_job(DropOffAggregator, %{})
  end

  describe "perform/1" do
    test "counts a pending drop-off whose 1-hour window has elapsed" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      viewer = insert(:viewer, organization: org)

      drop_off =
        insert_drop_off(%{
          organization: org,
          video: video,
          viewer: viewer,
          bucket: 5,
          max_position: 55.0,
          left_at: aged(61 * 60)
        })

      run_worker()

      bucket = Repo.get_by!(VideoDropOffBucket, video_id: video.id, bucket: 5)
      assert bucket.count == 1

      updated = Repo.get!(PlaybackDropOff, drop_off.id)
      assert updated.outcome == "counted"
      refute is_nil(updated.counted_at)
    end

    test "leaves rows younger than the window alone" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      viewer = insert(:viewer, organization: org)

      drop_off =
        insert_drop_off(%{
          organization: org,
          video: video,
          viewer: viewer,
          bucket: 2,
          max_position: 25.0,
          left_at: aged(30 * 60)
        })

      run_worker()

      refute Repo.get_by(VideoDropOffBucket, video_id: video.id, bucket: 2)
      assert Repo.get!(PlaybackDropOff, drop_off.id).counted_at == nil
    end

    test "discards when viewer returned via fresh Progress activity" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      viewer = insert(:viewer, organization: org)

      drop_off =
        insert_drop_off(%{
          organization: org,
          video: video,
          viewer: viewer,
          bucket: 3,
          max_position: 35.0,
          left_at: aged(2 * 60 * 60)
        })

      insert(:progress,
        organization: org,
        video: video,
        viewer: viewer,
        user: nil,
        position: 80.0,
        duration: 600.0,
        updated_at: aged(30 * 60)
      )

      run_worker()

      refute Repo.get_by(VideoDropOffBucket, video_id: video.id, bucket: 3)
      assert Repo.get!(PlaybackDropOff, drop_off.id).outcome == "discarded"
    end

    test "discards when viewer has completed the video" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      viewer = insert(:viewer, organization: org)

      drop_off =
        insert_drop_off(%{
          organization: org,
          video: video,
          viewer: viewer,
          bucket: 7,
          max_position: 75.0,
          left_at: aged(2 * 60 * 60)
        })

      insert(:progress,
        organization: org,
        video: video,
        viewer: viewer,
        user: nil,
        position: 600.0,
        duration: 600.0,
        completed: true,
        updated_at: aged(3 * 60 * 60)
      )

      run_worker()

      refute Repo.get_by(VideoDropOffBucket, video_id: video.id, bucket: 7)
      assert Repo.get!(PlaybackDropOff, drop_off.id).outcome == "discarded"
    end

    test "discards older drop-off when a newer one exists for the same video" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      viewer = insert(:viewer, organization: org)

      older =
        insert_drop_off(%{
          organization: org,
          video: video,
          viewer: viewer,
          bucket: 3,
          max_position: 35.0,
          left_at: aged(3 * 60 * 60)
        })

      newer =
        insert_drop_off(%{
          organization: org,
          video: video,
          viewer: viewer,
          bucket: 9,
          max_position: 95.0,
          left_at: aged(2 * 60 * 60)
        })

      run_worker()

      refute Repo.get_by(VideoDropOffBucket, video_id: video.id, bucket: 3)
      assert Repo.get_by!(VideoDropOffBucket, video_id: video.id, bucket: 9).count == 1
      assert Repo.get!(PlaybackDropOff, older.id).outcome == "discarded"
      assert Repo.get!(PlaybackDropOff, newer.id).outcome == "counted"
    end

    test "increments existing bucket counter on repeated drop-offs" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      viewer_a = insert(:viewer, organization: org)
      viewer_b = insert(:viewer, organization: org)

      insert_drop_off(%{
        organization: org,
        video: video,
        viewer: viewer_a,
        bucket: 4,
        max_position: 45.0,
        left_at: aged(2 * 60 * 60)
      })

      insert_drop_off(%{
        organization: org,
        video: video,
        viewer: viewer_b,
        bucket: 4,
        max_position: 48.0,
        left_at: aged(90 * 60)
      })

      run_worker()

      assert Repo.get_by!(VideoDropOffBucket, video_id: video.id, bucket: 4).count == 2
    end

    test "skips rows that have already been processed" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      viewer = insert(:viewer, organization: org)

      existing =
        insert(:video_drop_off_bucket,
          organization: org,
          video: video,
          bucket: 2,
          count: 5
        )

      insert_drop_off(%{
        organization: org,
        video: video,
        viewer: viewer,
        bucket: 2,
        max_position: 25.0,
        left_at: aged(3 * 60 * 60),
        counted_at: aged(2 * 60 * 60),
        outcome: "counted"
      })

      run_worker()

      reloaded = Repo.get!(VideoDropOffBucket, existing.id)
      assert reloaded.count == 5
    end

    test "handles user-scoped drop-offs (no viewer_id)" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      user = insert(:user)

      insert_drop_off(%{
        organization: org,
        video: video,
        viewer: nil,
        user: user,
        bucket: 6,
        max_position: 65.0,
        left_at: aged(2 * 60 * 60)
      })

      run_worker()

      assert Repo.get_by!(VideoDropOffBucket, video_id: video.id, bucket: 6).count == 1
    end
  end
end
