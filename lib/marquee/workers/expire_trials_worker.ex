defmodule Marquee.Workers.ExpireTrialsWorker do
  @moduledoc """
  Periodic job that transitions elapsed self-service trials to `past_due`.

  A `:trialing` platform subscription whose `trial_end` has passed with no
  payment is moved to `:past_due`, which puts the org into soft-lock: the
  operator is blocked from new uploads, adding viewers, and branding changes
  until they add payment (`Marquee.PlatformBilling.soft_locked?/1`), while the
  viewer site and existing viewers are unaffected.

  Runs daily via Oban cron. Cross-tenant by design — this is a platform-level
  operation. No `organization_id` in args (documented Admin exception).
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Marquee.PlatformBilling

  @impl true
  def perform(%Oban.Job{}) do
    PlatformBilling.list_expirable_trials()
    |> Enum.each(&expire/1)

    :ok
  end

  defp expire(sub) do
    case PlatformBilling.expire_trial(sub) do
      {:ok, _sub} ->
        Logger.info("Expired trial subscription",
          org_id: sub.organization_id,
          platform_subscription_id: sub.id
        )

      {:error, reason, _detail} ->
        Logger.warning("Failed to expire trial subscription",
          org_id: sub.organization_id,
          platform_subscription_id: sub.id,
          reason: inspect(reason)
        )
    end
  end
end
