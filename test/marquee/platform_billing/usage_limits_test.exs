defmodule Marquee.PlatformBilling.UsageLimitsTest do
  use Marquee.DataCase, async: true

  alias Marquee.PlatformBilling.UsageLimits

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

  describe "check_upload/1" do
    test "returns :ok when under all limits" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_videos: 50, max_total_duration_seconds: 18_000)
      insert(:platform_subscription, organization: org, platform_plan: plan)

      assert UsageLimits.check_upload(org) == :ok
    end

    test "returns plan_limit_reached with seconds unit when total duration is reached" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_videos: 50, max_total_duration_seconds: 100)
      insert(:platform_subscription, organization: org, platform_plan: plan)
      insert(:video, organization: org, mux_status: "ready", duration: 120.0)

      assert {:error, :plan_limit_reached, %{unit: :seconds, reached: true}} =
               UsageLimits.check_upload(org)
    end

    test "treats -1 duration as unlimited" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_videos: 50, max_total_duration_seconds: -1)
      insert(:platform_subscription, organization: org, platform_plan: plan)
      insert(:video, organization: org, mux_status: "ready", duration: 99_999.0)

      assert UsageLimits.check_upload(org) == :ok
    end

    test "returns trial_expired when the trial window has elapsed" do
      org = insert(:organization)
      past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      insert(:platform_subscription,
        organization: org,
        platform_plan: nil,
        stripe_subscription_id: nil,
        status: :trialing,
        trial_end: past
      )

      assert {:error, :trial_expired, %{trial_end: %DateTime{}}} = UsageLimits.check_upload(org)
    end
  end

  describe "check_register_viewer/1 and can_register_viewer?/1" do
    test "allows viewers under the cap" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_viewers: 2)
      insert(:platform_subscription, organization: org, platform_plan: plan)

      assert UsageLimits.can_register_viewer?(org)
      assert UsageLimits.check_register_viewer(org) == :ok
    end

    test "blocks viewers at the cap" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_viewers: 1)
      insert(:platform_subscription, organization: org, platform_plan: plan)
      insert(:viewer, organization: org)

      refute UsageLimits.can_register_viewer?(org)

      assert {:error, :plan_limit_reached, %{reached: true}} =
               UsageLimits.check_register_viewer(org)
    end

    test "treats nil viewer limit as unlimited (default free plan)" do
      org = insert(:organization)
      insert(:viewer, organization: org)

      assert UsageLimits.can_register_viewer?(org)
    end
  end

  describe "check_custom_domain/1 and can_use_custom_domain?/1" do
    test "trial plan denies custom domain" do
      org = insert(:organization)
      {:ok, _sub} = Marquee.PlatformBilling.start_trial(org)

      refute UsageLimits.can_use_custom_domain?(org)

      assert {:error, :plan_limit_reached, %{feature: :custom_domain}} =
               UsageLimits.check_custom_domain(org)
    end

    test "a plan with allow_custom_domain permits it" do
      org = insert(:organization)
      plan = insert(:platform_plan, allow_custom_domain: true)
      insert(:platform_subscription, organization: org, platform_plan: plan)

      assert UsageLimits.can_use_custom_domain?(org)
      assert UsageLimits.check_custom_domain(org) == :ok
    end
  end
end
