defmodule Bobine.PlatformBilling.UsageLimitsTest do
  use Bobine.DataCase, async: true

  alias Bobine.PlatformBilling.UsageLimits

  describe "can_upload_video?/1" do
    test "returns true when under limit" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_videos: 50)
      insert(:platform_subscription, organization: org, platform_plan: plan)

      assert UsageLimits.can_upload_video?(org) == true
    end

    test "returns false when at limit" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_videos: 2)
      insert(:platform_subscription, organization: org, platform_plan: plan)

      # Insert 2 videos to reach the limit
      insert(:video, organization: org)
      insert(:video, organization: org)

      assert UsageLimits.can_upload_video?(org) == false
    end

    test "returns true when limit is nil (unlimited)" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_videos: nil)
      insert(:platform_subscription, organization: org, platform_plan: plan)

      assert UsageLimits.can_upload_video?(org) == true
    end
  end

  describe "can_add_team_member?/1" do
    test "respects seat limits" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_team_seats: 1)
      insert(:platform_subscription, organization: org, platform_plan: plan)

      # There's already 0 memberships for this org in the factory
      assert UsageLimits.can_add_team_member?(org) == true

      # Add a membership to reach the limit
      insert(:membership, organization: org)

      assert UsageLimits.can_add_team_member?(org) == false
    end
  end

  describe "can_add_webhook_endpoint?/1" do
    test "respects endpoint limits" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_webhook_endpoints: 1)
      insert(:platform_subscription, organization: org, platform_plan: plan)

      assert UsageLimits.can_add_webhook_endpoint?(org) == true

      insert(:webhook_endpoint, organization: org)

      assert UsageLimits.can_add_webhook_endpoint?(org) == false
    end
  end

  describe "video_limit_status/1" do
    test "returns current count and limit" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_videos: 50)
      insert(:platform_subscription, organization: org, platform_plan: plan)
      insert(:video, organization: org)

      status = UsageLimits.video_limit_status(org)
      assert status.current == 1
      assert status.limit == 50
      assert status.reached == false
    end

    test "reached is true when at limit" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_videos: 1)
      insert(:platform_subscription, organization: org, platform_plan: plan)
      insert(:video, organization: org)

      status = UsageLimits.video_limit_status(org)
      assert status.reached == true
    end
  end

  describe "org with no subscription" do
    test "gets default free limits" do
      org = insert(:organization)

      plan = UsageLimits.get_plan_for_org(org)
      assert plan.max_videos == 5
      assert plan.max_monthly_views == 500
      assert plan.max_team_seats == 1
      assert plan.max_webhook_endpoints == 0
    end
  end
end
