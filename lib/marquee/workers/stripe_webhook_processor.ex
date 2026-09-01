defmodule Marquee.Workers.StripeWebhookProcessor do
  @moduledoc """
  Oban worker that processes Stripe webhook events asynchronously.

  Distinguishes between platform events (no connected account — org subscribing
  to Marquee) and connected account events (viewer subscribing to an org).
  """

  use Oban.Worker,
    queue: :stripe,
    unique: [period: 60, fields: [:args], keys: [:event_id]]

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Marquee.Accounts
  alias Marquee.Admin
  alias Marquee.Billing
  alias Marquee.PlatformBilling
  alias Marquee.Repo
  alias Marquee.Streaming
  alias Marquee.Viewers

  @impl true
  def perform(%Oban.Job{args: %{"event" => event} = args, attempt: attempt}) do
    Marquee.Otel.extract_trace_context(args["trace_context"])

    event_type = event["type"]
    data = event["data"]["object"]
    connect_account_id = event["account"]

    Logger.metadata(
      event_type: event_type,
      stripe_event_id: event["id"],
      worker: "StripeWebhookProcessor"
    )

    Tracer.with_span "marquee.worker.stripe_webhook_processor",
                     %{"stripe.event_type" => event_type, "oban.attempt" => attempt} do
      handle_event(event_type, data, connect_account_id)
    end
  end

  # ── Platform events (no connected account — org subscribing to Marquee) ──

  defp handle_event("checkout.session.completed", session, nil) do
    org_id = get_in(session, ["metadata", "organization_id"])
    plan_id = get_in(session, ["metadata", "platform_plan_id"])
    attribute_to_org(org_id)

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
        attribute_to_org(sub.organization_id)

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
        attribute_to_org(sub.organization_id)
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
        attribute_to_org(sub.organization_id)
        PlatformBilling.mark_platform_payment_failed(sub)
        Marquee.Metrics.platform_payment_failed(sub.organization_id)
        Logger.warning("Platform payment failed", org_id: sub.organization_id)
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  defp handle_event("invoice.payment_succeeded", invoice, nil) do
    case PlatformBilling.get_subscription_by_stripe_id(invoice["subscription"]) do
      {:ok, sub} ->
        attribute_to_org(sub.organization_id)
        PlatformBilling.mark_platform_payment_succeeded(sub)
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # Connected account events (viewer subscriptions)
  # These have a non-nil connect_account_id
  # ══════════════════════════════════════════════════════════════════════

  defp handle_event("checkout.session.completed", session, connect_account_id)
       when not is_nil(connect_account_id) do
    with {:ok, org} <- resolve_connected_org(connect_account_id),
         {:ok, viewer} <- find_or_create_viewer_from_checkout(org, session),
         {:ok, subscription} <- Billing.create_subscription_from_checkout(org, viewer, session) do
      Billing.activate_viewer_subscription(org, viewer, subscription)
      Marquee.Metrics.subscription_created(org.id, "viewer")

      Logger.info("Viewer subscription created",
        org_id: org.id,
        viewer_id: viewer.id,
        stripe_subscription_id: subscription.stripe_subscription_id
      )

      :ok
    else
      {:error, :not_found} ->
        Logger.warning("Connected account org not found",
          connect_account_id: connect_account_id
        )

        :ok

      {:error, reason} ->
        Logger.error("Connected checkout processing failed",
          connect_account_id: connect_account_id,
          reason: inspect(reason)
        )

        :ok

      {:error, _type, _detail} ->
        Logger.error("Connected checkout processing failed",
          connect_account_id: connect_account_id
        )

        :ok
    end
  end

  defp handle_event("customer.subscription.updated", data, connect_account_id)
       when not is_nil(connect_account_id) do
    with {:ok, org} <- resolve_connected_org(connect_account_id),
         {:ok, subscription} <- Billing.get_viewer_subscription_by_stripe_id(org, data["id"]) do
      {:ok, updated} = Billing.update_subscription_from_stripe(org, subscription, data)
      viewer = Viewers.get_viewer!(org, updated.viewer_id)
      Billing.sync_viewer_subscription_status(viewer, updated)
      :ok
    else
      {:error, :not_found} ->
        Logger.warning("Connected subscription not found for update",
          stripe_subscription_id: data["id"],
          connect_account_id: connect_account_id
        )

        :ok
    end
  end

  defp handle_event("invoice.payment_failed", invoice, connect_account_id)
       when not is_nil(connect_account_id) do
    with {:ok, org} <- resolve_connected_org(connect_account_id),
         {:ok, subscription} <-
           Billing.get_viewer_subscription_by_stripe_id(org, invoice["subscription"]) do
      viewer = Viewers.get_viewer!(org, subscription.viewer_id)
      Billing.mark_payment_failed(org, viewer, subscription)
      Marquee.Metrics.viewer_payment_failed(org.id, subscription.plan_id)

      Logger.warning("Viewer payment failed",
        org_id: org.id,
        viewer_id: viewer.id
      )

      :ok
    else
      {:error, :not_found} -> :ok
    end
  end

  defp handle_event("invoice.payment_succeeded", invoice, connect_account_id)
       when not is_nil(connect_account_id) do
    with {:ok, org} <- resolve_connected_org(connect_account_id),
         {:ok, subscription} <-
           Billing.get_viewer_subscription_by_stripe_id(org, invoice["subscription"]) do
      viewer = Viewers.get_viewer!(org, subscription.viewer_id)
      Billing.mark_payment_succeeded(org, viewer, subscription)
      :ok
    else
      {:error, :not_found} -> :ok
    end
  end

  defp handle_event("customer.subscription.deleted", data, connect_account_id)
       when not is_nil(connect_account_id) do
    with {:ok, org} <- resolve_connected_org(connect_account_id),
         {:ok, subscription} <- Billing.get_viewer_subscription_by_stripe_id(org, data["id"]) do
      viewer = Viewers.get_viewer!(org, subscription.viewer_id)
      Billing.cancel_subscription_from_stripe(org, viewer, subscription)
      Marquee.Metrics.subscription_canceled(org.id, "viewer")
      :ok
    else
      {:error, :not_found} -> :ok
    end
  end

  defp handle_event("payment_intent.succeeded", payment_intent, connect_account_id)
       when not is_nil(connect_account_id) do
    metadata = payment_intent["metadata"] || %{}

    if metadata["marquee_type"] == "ppv" do
      handle_ppv_payment_intent_succeeded(payment_intent, metadata, connect_account_id)
    else
      :ok
    end
  end

  defp handle_event("customer.subscription.trial_will_end", _data, connect_account_id)
       when not is_nil(connect_account_id) do
    # Trial ending notification — log for now, full notification system is future work
    Logger.info("Viewer trial ending soon",
      connect_account_id: connect_account_id
    )

    :ok
  end

  # Catch-all for unhandled connected account events
  defp handle_event(_type, _data, connect_account_id) when not is_nil(connect_account_id) do
    Logger.debug("Unhandled connected account event",
      connect_account_id: connect_account_id
    )

    :ok
  end

  # ── Unhandled platform events ──

  defp handle_event(type, _data, nil) do
    Logger.debug("Unhandled platform Stripe event", type: type)
    :ok
  end

  # ── PPV helpers ──

  defp handle_ppv_payment_intent_succeeded(payment_intent, metadata, connect_account_id) do
    live_event_id = metadata["marquee_live_event_id"]
    viewer_id = metadata["marquee_viewer_id"]
    payment_intent_id = payment_intent["id"]

    with {:org, {:ok, org}} <- {:org, resolve_connected_org(connect_account_id)},
         {:event, {:ok, event}} <- {:event, fetch_ppv_live_event(org, live_event_id)},
         {:viewer, viewer} when not is_nil(viewer) <-
           {:viewer, Viewers.get_viewer_by_id(viewer_id)},
         {:idempotent, false} <-
           {:idempotent, ticket_exists_for_payment_intent?(payment_intent_id)},
         {:ok, _ticket} <-
           Streaming.create_ticket(event, viewer, %{
             stripe_payment_intent_id: payment_intent_id,
             purchased_at: DateTime.utc_now(),
             amount_cents: payment_intent["amount"]
           }) do
      Logger.info("PPV ticket created",
        org_id: org.id,
        viewer_id: viewer_id,
        live_event_id: live_event_id,
        payment_intent_id: payment_intent_id
      )

      :ok
    else
      {:idempotent, true} ->
        Logger.info("PPV ticket already exists, skipping",
          payment_intent_id: payment_intent_id
        )

        :ok

      {:org, {:error, :not_found}} ->
        Logger.warning("PPV: connected org not found",
          connect_account_id: connect_account_id
        )

        :ok

      {:event, {:error, :not_found}} ->
        Logger.warning("PPV: live event not found",
          live_event_id: live_event_id
        )

        :ok

      {:viewer, nil} ->
        Logger.warning("PPV: viewer not found",
          viewer_id: viewer_id
        )

        :ok

      {:error, :validation, _changeset} ->
        Logger.error("PPV ticket creation failed due to validation error",
          payment_intent_id: payment_intent_id
        )

        :ok

      error ->
        Logger.error("PPV ticket creation failed",
          payment_intent_id: payment_intent_id,
          reason: inspect(error)
        )

        :ok
    end
  end

  defp fetch_ppv_live_event(org, live_event_id) do
    Streaming.get_live_event(org, live_event_id)
  end

  defp ticket_exists_for_payment_intent?(payment_intent_id) do
    import Ecto.Query, warn: false
    alias Marquee.Streaming.LiveEventTicket

    Repo.exists?(
      from(t in LiveEventTicket,
        where: t.stripe_payment_intent_id == ^payment_intent_id,
        where: is_nil(t.deleted_at)
      )
    )
  end

  # ── Connected account helpers ──

  defp find_or_create_viewer_from_checkout(org, session) do
    email =
      session["customer_email"] ||
        get_in(session, ["customer_details", "email"])

    case Viewers.get_viewer_by_email(org, email) do
      nil ->
        Viewers.register_viewer(org, %{
          email: email,
          stripe_customer_id: session["customer"],
          subscription_status: "active"
        })

      viewer ->
        if is_nil(viewer.stripe_customer_id) do
          viewer
          |> Ecto.Changeset.change(stripe_customer_id: session["customer"])
          |> Marquee.Repo.update()
        else
          {:ok, viewer}
        end
    end
  end

  defp plan_changed?(%{platform_plan_id: old_id}, %{platform_plan_id: new_id}) do
    old_id != new_id
  end

  defp get_organization(org_id) do
    {:ok, Admin.get_organization!(org_id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp resolve_connected_org(connect_account_id) do
    case Accounts.get_organization_by_stripe_connect_id(connect_account_id) do
      {:ok, org} ->
        attribute_to_org(org.id)
        {:ok, org}

      error ->
        error
    end
  end

  defp attribute_to_org(org_id) when is_binary(org_id) do
    Logger.metadata(org_id: org_id)
    Tracer.set_attributes([{"marquee.org.id", org_id}])
    :ok
  end

  defp attribute_to_org(_), do: :ok
end
