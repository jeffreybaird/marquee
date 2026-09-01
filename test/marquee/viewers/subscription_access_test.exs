defmodule Marquee.Viewers.SubscriptionAccessTest do
  use Marquee.DataCase

  alias Marquee.Viewers.SubscriptionAccess
  alias Marquee.Viewers.Viewer

  describe "has_access?/1" do
    test "returns true for active subscription" do
      viewer = build(:viewer, subscription_status: "active")
      assert SubscriptionAccess.has_access?(viewer)
    end

    test "returns true for trial with future expiry" do
      viewer =
        build(:viewer,
          subscription_status: "trial",
          trial_expires_at: DateTime.add(DateTime.utc_now(), 7, :day)
        )

      assert SubscriptionAccess.has_access?(viewer)
    end

    test "returns false for trial with past expiry" do
      viewer =
        build(:viewer,
          subscription_status: "trial",
          trial_expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
        )

      refute SubscriptionAccess.has_access?(viewer)
    end

    test "returns false for trial with nil expiry (treated as expired)" do
      viewer = build(:viewer, subscription_status: "trial", trial_expires_at: nil)
      refute SubscriptionAccess.has_access?(viewer)
    end

    test "returns true for past_due subscription" do
      viewer = build(:viewer, subscription_status: "past_due")
      assert SubscriptionAccess.has_access?(viewer)
    end

    test "returns false for none subscription" do
      viewer = build(:viewer, subscription_status: "none")
      refute SubscriptionAccess.has_access?(viewer)
    end

    test "returns false for canceled subscription" do
      viewer = build(:viewer, subscription_status: "canceled")
      refute SubscriptionAccess.has_access?(viewer)
    end

    test "returns false for expired subscription" do
      viewer = build(:viewer, subscription_status: "expired")
      refute SubscriptionAccess.has_access?(viewer)
    end
  end

  describe "trial_expired?/1" do
    test "returns true when trial_expires_at is nil" do
      viewer = %Viewer{trial_expires_at: nil}
      assert SubscriptionAccess.trial_expired?(viewer)
    end

    test "returns false when trial_expires_at is in the future" do
      viewer = %Viewer{trial_expires_at: DateTime.add(DateTime.utc_now(), 7, :day)}
      refute SubscriptionAccess.trial_expired?(viewer)
    end

    test "returns true when trial_expires_at is in the past" do
      viewer = %Viewer{trial_expires_at: DateTime.add(DateTime.utc_now(), -1, :day)}
      assert SubscriptionAccess.trial_expired?(viewer)
    end
  end
end
