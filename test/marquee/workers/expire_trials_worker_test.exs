defmodule Marquee.Workers.ExpireTrialsWorkerTest do
  use Marquee.DataCase, async: true
  use Oban.Testing, repo: Marquee.Repo

  alias Marquee.Billing.PlatformSubscription
  alias Marquee.Repo
  alias Marquee.Workers.ExpireTrialsWorker

  defp past, do: DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
  defp future, do: DateTime.utc_now() |> DateTime.add(5, :day) |> DateTime.truncate(:second)

  defp trial(org, trial_end) do
    insert(:platform_subscription,
      organization: org,
      platform_plan: nil,
      stripe_subscription_id: nil,
      status: :trialing,
      trial_end: trial_end
    )
  end

  describe "perform/1" do
    test "transitions an elapsed trial to past_due" do
      sub = trial(insert(:organization), past())

      assert :ok = perform_job(ExpireTrialsWorker, %{})
      assert Repo.get!(PlatformSubscription, sub.id).status == :past_due
    end

    test "leaves an active trial untouched" do
      sub = trial(insert(:organization), future())

      assert :ok = perform_job(ExpireTrialsWorker, %{})
      assert Repo.get!(PlatformSubscription, sub.id).status == :trialing
    end

    test "leaves an active paid subscription untouched" do
      sub = insert(:platform_subscription, organization: insert(:organization), status: :active)

      assert :ok = perform_job(ExpireTrialsWorker, %{})
      assert Repo.get!(PlatformSubscription, sub.id).status == :active
    end
  end
end
