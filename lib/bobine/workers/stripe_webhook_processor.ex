defmodule Bobine.Workers.StripeWebhookProcessor do
  @moduledoc """
  Oban worker that processes Stripe webhook events asynchronously.

  Distinguishes between platform events (no connected account — org subscribing
  to Bobine) and connected account events (viewer subscribing to an org).
  """

  use Oban.Worker,
    queue: :stripe,
    unique: [period: 60, fields: [:args], keys: [:event_id]]

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Bobine.PlatformBilling
  alias Bobine.Admin

  @impl true
  def perform(%Oban.Job{args: %{"event" => event}, attempt: attempt}) do
    event_type = event["type"]
    data = event["data"]["object"]
    connect_account_id = event["account"]

    Logger.metadata(
      event_type: event_type,
      stripe_event_id: event["id"],
      worker: "StripeWebhookProcessor"
    )

    Tracer.with_span "bobine.worker.stripe_webhook_processor",
                     %{"stripe.event_type" => event_type, "oban.attempt" => attempt} do
      handle_event(event_type, data, connect_account_id)
    end
  end

  # ── Platform events (no connected account — org subscribing to Bobine) ──

  defp handle_event("checkout.session.completed", session, nil) do
    org_id = get_in(session, ["metadata", "organization_id"])
    plan_id = get_in(session, ["metadata", "platform_plan_id"])

    if is_nil(org_id) or is_nil(plan_id) do
      Logger.warning("Platform checkout missing metadata",
        org_id: org_id,
        plan_id: plan_id
      )

      :ok
    else
      with {:ok, org} <- get_organization(org_id),
           {:ok, plan} <- PlatformBilling.get_platform_plan(plan_id),
           {:ok, _sub} <- PlatformBilling.create_subscription_from_checkout(org, plan, session) do
        PlatformBilling.sync_features_to_plan(org, plan)
        Logger.info("Platform subscription created", org_id: org_id, plan: plan.slug)
        :ok
      else
        {:error, reason} ->
          Logger.error("Platform checkout failed", org_id: org_id, reason: inspect(reason))
          :ok

        {:error, _type, _detail} ->
          Logger.error("Platform checkout failed", org_id: org_id)
          :ok
      end
    end
  end

  defp handle_event("customer.subscription.updated", subscription_data, nil) do
    case PlatformBilling.get_subscription_by_stripe_id(subscription_data["id"]) do
      {:ok, sub} ->
        {:ok, updated_sub} =
          PlatformBilling.update_subscription_from_stripe(sub, subscription_data)

        if plan_changed?(sub, updated_sub) do
          org = Admin.get_organization!(sub.organization_id)
          new_plan = PlatformBilling.get_platform_plan!(updated_sub.platform_plan_id)
          PlatformBilling.sync_features_to_plan(org, new_plan)
          Logger.info("Platform plan changed", org_id: org.id, plan: new_plan.slug)
        end

        :ok

      {:error, :not_found} ->
        Logger.warning("Platform subscription not found",
          stripe_id: subscription_data["id"]
        )

        :ok
    end
  end

  defp handle_event("customer.subscription.deleted", subscription_data, nil) do
    case PlatformBilling.get_subscription_by_stripe_id(subscription_data["id"]) do
      {:ok, sub} ->
        org = Admin.get_organization!(sub.organization_id)
        PlatformBilling.cancel_subscription_from_stripe(sub)
        PlatformBilling.sync_features_to_plan(org, PlatformBilling.default_free_plan())
        Logger.info("Platform subscription canceled", org_id: org.id)
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  defp handle_event("invoice.payment_failed", invoice, nil) do
    case PlatformBilling.get_subscription_by_stripe_id(invoice["subscription"]) do
      {:ok, sub} ->
        PlatformBilling.mark_platform_payment_failed(sub)
        Bobine.Metrics.platform_payment_failed(sub.organization_id)
        Logger.warning("Platform payment failed", org_id: sub.organization_id)
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  defp handle_event("invoice.payment_succeeded", invoice, nil) do
    case PlatformBilling.get_subscription_by_stripe_id(invoice["subscription"]) do
      {:ok, sub} ->
        PlatformBilling.mark_platform_payment_succeeded(sub)
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  # ── Connected account events (viewer subscription) — future handlers ──

  defp handle_event(_type, _data, connect_account_id) when not is_nil(connect_account_id) do
    # Connected account events will be handled in Feature 05a
    Logger.debug("Ignoring connected account event",
      connect_account_id: connect_account_id
    )

    :ok
  end

  # ── Unhandled platform events ──

  defp handle_event(type, _data, nil) do
    Logger.debug("Unhandled platform Stripe event", type: type)
    :ok
  end

  defp plan_changed?(%{platform_plan_id: old_id}, %{platform_plan_id: new_id}) do
    old_id != new_id
  end

  defp get_organization(org_id) do
    try do
      {:ok, Admin.get_organization!(org_id)}
    rescue
      Ecto.NoResultsError -> {:error, :not_found}
    end
  end
end
