defmodule Bobine.Engagement.PlaybackDropOffTest do
  use Bobine.DataCase, async: true

  alias Bobine.Engagement
  alias Bobine.Engagement.PlaybackDropOff

  doctest PlaybackDropOff

  describe "record_drop_off/1" do
    test "inserts a drop-off with bucket computed from max_position" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      viewer = insert(:viewer, organization: org)

      assert {:ok, drop_off} =
               Engagement.record_drop_off(%{
                 organization_id: org.id,
                 video_id: video.id,
                 viewer_id: viewer.id,
                 max_position: 47.5,
                 video_duration: 600.0
               })

      assert drop_off.bucket == 4
      assert drop_off.max_position == 47.5
      assert drop_off.video_duration == 600.0
      assert drop_off.left_at != nil
      assert drop_off.counted_at == nil
    end

    test "accepts string keys from LiveView events" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      viewer = insert(:viewer, organization: org)

      assert {:ok, drop_off} =
               Engagement.record_drop_off(%{
                 "organization_id" => org.id,
                 "video_id" => video.id,
                 "viewer_id" => viewer.id,
                 "max_position" => "125.0",
                 "video_duration" => "600.0"
               })

      assert drop_off.bucket == 12
    end

    test "accepts user_id when viewer_id is absent" do
      org = insert(:organization)
      user = insert(:user)
      video = insert(:video, organization: org)

      assert {:ok, drop_off} =
               Engagement.record_drop_off(%{
                 organization_id: org.id,
                 video_id: video.id,
                 user_id: user.id,
                 max_position: 10.0
               })

      assert drop_off.user_id == user.id
      assert drop_off.viewer_id == nil
      assert drop_off.bucket == 1
    end

    test "returns validation error when both viewer_id and user_id are missing" do
      org = insert(:organization)
      video = insert(:video, organization: org)

      assert {:error, :validation, changeset} =
               Engagement.record_drop_off(%{
                 organization_id: org.id,
                 video_id: video.id,
                 max_position: 10.0
               })

      refute changeset.valid?
      assert %{viewer_id: ["either viewer_id or user_id must be set"]} = errors_on(changeset)
    end

    test "returns validation error when organization_id is missing" do
      video = insert(:video)
      viewer = insert(:viewer)

      assert {:error, :validation, changeset} =
               Engagement.record_drop_off(%{
                 video_id: video.id,
                 viewer_id: viewer.id,
                 max_position: 10.0
               })

      refute changeset.valid?
      assert %{organization_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "coerces integer max_position to float" do
      org = insert(:organization)
      video = insert(:video, organization: org)
      viewer = insert(:viewer, organization: org)

      assert {:ok, drop_off} =
               Engagement.record_drop_off(%{
                 organization_id: org.id,
                 video_id: video.id,
                 viewer_id: viewer.id,
                 max_position: 30
               })

      assert drop_off.max_position == 30.0
      assert drop_off.bucket == 3
    end
  end

  describe "bucket_for/1" do
    test "returns 0 for positions under 10 seconds" do
      assert PlaybackDropOff.bucket_for(0.0) == 0
      assert PlaybackDropOff.bucket_for(9.99) == 0
    end

    test "returns consecutive buckets for 10-second intervals" do
      assert PlaybackDropOff.bucket_for(10.0) == 1
      assert PlaybackDropOff.bucket_for(19.99) == 1
      assert PlaybackDropOff.bucket_for(20.0) == 2
    end

    test "handles large positions" do
      assert PlaybackDropOff.bucket_for(3600.0) == 360
    end
  end
end
