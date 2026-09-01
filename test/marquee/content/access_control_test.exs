defmodule Marquee.Content.AccessControlTest do
  use Marquee.DataCase

  alias Marquee.Content.AccessControl

  describe "can_watch?/2" do
    test "public video is accessible with nil viewer" do
      video = %{visibility: "public"}
      assert AccessControl.can_watch?(video, nil)
    end

    test "public video is accessible with any viewer" do
      video = %{visibility: "public"}
      viewer = build(:viewer, subscription_status: "none")
      assert AccessControl.can_watch?(video, viewer)
    end

    test "free_with_account video is accessible with any viewer" do
      video = %{visibility: "free_with_account"}
      viewer = build(:viewer, subscription_status: "none")
      assert AccessControl.can_watch?(video, viewer)
    end

    test "free_with_account video is not accessible with nil viewer" do
      video = %{visibility: "free_with_account"}
      refute AccessControl.can_watch?(video, nil)
    end

    test "subscribers_only video is accessible with active subscriber" do
      video = %{visibility: "subscribers_only"}
      viewer = build(:subscribed_viewer)
      assert AccessControl.can_watch?(video, viewer)
    end

    test "subscribers_only video is not accessible with no subscription" do
      video = %{visibility: "subscribers_only"}
      viewer = build(:viewer, subscription_status: "none")
      refute AccessControl.can_watch?(video, viewer)
    end

    test "subscribers_only video is not accessible with nil viewer" do
      video = %{visibility: "subscribers_only"}
      refute AccessControl.can_watch?(video, nil)
    end

    test "subscribers_only video is accessible with past_due subscriber" do
      video = %{visibility: "subscribers_only"}
      viewer = build(:viewer, subscription_status: "past_due")
      assert AccessControl.can_watch?(video, viewer)
    end

    test "subscribers_only video is not accessible with canceled subscription" do
      video = %{visibility: "subscribers_only"}
      viewer = build(:viewer, subscription_status: "canceled")
      refute AccessControl.can_watch?(video, viewer)
    end

    test "subscribers_only video is accessible with active trial" do
      video = %{visibility: "subscribers_only"}

      viewer =
        build(:viewer,
          subscription_status: "trial",
          trial_expires_at: DateTime.add(DateTime.utc_now(), 7, :day)
        )

      assert AccessControl.can_watch?(video, viewer)
    end

    test "subscribers_only video is not accessible with expired trial" do
      video = %{visibility: "subscribers_only"}

      viewer =
        build(:viewer,
          subscription_status: "trial",
          trial_expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
        )

      refute AccessControl.can_watch?(video, viewer)
    end
  end
end
