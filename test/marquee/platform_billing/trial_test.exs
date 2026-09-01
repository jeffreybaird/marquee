defmodule Marquee.PlatformBilling.TrialTest do
  use Marquee.DataCase, async: true

  alias Marquee.Billing.PlatformSubscription
  alias Marquee.PlatformBilling
  alias Marquee.PlatformBilling.UsageLimits

  describe "start_trial/1" do
    test "creates a trialing subscription with no plan or stripe subscription" do
      org = insert(:organization)

      assert {:ok, sub} = PlatformBilling.start_trial(org)
      assert sub.status == :trialing
      assert sub.platform_plan_id == nil
      assert sub.stripe_subscription_id == nil
      assert sub.organization_id == org.id
    end

    test "sets trial_end trial_days out from now" do
      org = insert(:organization)

      {:ok, sub} = PlatformBilling.start_trial(org)

      expected = DateTime.add(sub.trial_start, PlatformBilling.trial_days(), :day)
      assert DateTime.compare(sub.trial_end, expected) == :eq
    end

    test "is rejected for an org that already has a subscription" do
      org = insert(:organization)
      insert(:platform_subscription, organization: org)

      assert {:error, :validation, changeset} = PlatformBilling.start_trial(org)
      assert errors_on(changeset)[:organization_id]
    end
  end

  describe "get_plan_for_org/1 for a trial" do
    test "returns the trial plan struct" do
      org = insert(:organization)
      {:ok, _sub} = PlatformBilling.start_trial(org)

      plan = UsageLimits.get_plan_for_org(org)

      assert plan.slug == "trial"
      assert plan.max_total_duration_seconds == PlatformBilling.trial_video_seconds()
      assert plan.max_viewers == PlatformBilling.trial_max_viewers()
      assert plan.allow_custom_domain == false
    end
  end

  describe "soft_locked?/1" do
    test "false while the trial is active" do
      org = insert(:organization)
      {:ok, _sub} = PlatformBilling.start_trial(org)

      refute PlatformBilling.soft_locked?(org)
    end

    test "true once the trial window has elapsed with no payment" do
      org = insert(:organization)
      past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      insert(:platform_subscription,
        organization: org,
        platform_plan: nil,
        stripe_subscription_id: nil,
        status: :trialing,
        trial_end: past
      )

      assert PlatformBilling.soft_locked?(org)
    end

    test "false for an org with no subscription" do
      refute PlatformBilling.soft_locked?(insert(:organization))
    end

    test "false for an active paid subscription" do
      org = insert(:organization)
      insert(:platform_subscription, organization: org, status: :active)

      refute PlatformBilling.soft_locked?(org)
    end
  end

  describe "list_expirable_trials/1 and expire_trial/1" do
    test "lists only elapsed trialing subscriptions" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      past = DateTime.add(now, -1, :day)
      future = DateTime.add(now, 5, :day)

      elapsed_org = insert(:organization)

      elapsed =
        insert(:platform_subscription,
          organization: elapsed_org,
          platform_plan: nil,
          stripe_subscription_id: nil,
          status: :trialing,
          trial_end: past
        )

      insert(:platform_subscription,
        organization: insert(:organization),
        platform_plan: nil,
        stripe_subscription_id: nil,
        status: :trialing,
        trial_end: future
      )

      insert(:platform_subscription, organization: insert(:organization), status: :active)

      ids = PlatformBilling.list_expirable_trials(now) |> Enum.map(& &1.id)

      assert ids == [elapsed.id]
    end

    test "transitions an elapsed trial to past_due" do
      org = insert(:organization)
      past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      sub =
        insert(:platform_subscription,
          organization: org,
          platform_plan: nil,
          stripe_subscription_id: nil,
          status: :trialing,
          trial_end: past
        )

      assert {:ok, updated} = PlatformBilling.expire_trial(sub)
      assert updated.status == :past_due
      assert Repo.get!(PlatformSubscription, sub.id).status == :past_due
    end
  end
end
