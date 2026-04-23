defmodule Bobine.Workers.RefundPpvTicketsWorker do
  @moduledoc """
  Oban worker that issues Stripe refunds for all non-refunded PPV tickets
  when a live event is canceled.

  Each ticket is processed independently — a failure on one ticket is logged
  but does not prevent processing the remaining tickets.

  Triggered by `Bobine.Streaming.cancel_live_event/2` when the event has
  `access_type: "pay_per_view"`.
  """

  use Oban.Worker, queue: :stripe

  import Ecto.Query, warn: false

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Bobine.Accounts.Scope
  alias Bobine.Repo
  alias Bobine.Streaming
  alias Bobine.Streaming.LiveEventTicket

  @impl true
  def perform(%Oban.Job{
        args: %{"live_event_id" => live_event_id, "organization_id" => org_id} = args
      }) do
    Bobine.Otel.extract_trace_context(args["trace_context"])

    Logger.metadata(
      live_event_id: live_event_id,
      org_id: org_id,
      worker: "RefundPpvTicketsWorker"
    )

    Tracer.with_span "bobine.worker.refund_ppv_tickets",
                     %{"bobine.live_event.id" => live_event_id, "bobine.org.id" => org_id} do
      tickets = fetch_refundable_tickets(live_event_id, org_id)

      Logger.info("Refunding PPV tickets for canceled event",
        live_event_id: live_event_id,
        org_id: org_id,
        ticket_count: length(tickets)
      )

      Enum.each(tickets, &refund_ticket_safely(live_event_id, org_id, &1))

      :ok
    end
  end

  defp fetch_refundable_tickets(live_event_id, org_id) do
    LiveEventTicket
    |> where(live_event_id: ^live_event_id, organization_id: ^org_id)
    |> where([t], is_nil(t.refunded_at))
    |> where([t], is_nil(t.deleted_at))
    |> Repo.all()
  end

  defp refund_ticket_safely(live_event_id, org_id, ticket) do
    stripe_client = Application.get_env(:bobine, :stripe_client, Bobine.Billing.StripeClient)

    with {:stripe, {:ok, _refund}} <-
           {:stripe, issue_stripe_refund(stripe_client, ticket)},
         {:db, {:ok, _updated}} <-
           {:db, mark_ticket_refunded(ticket, org_id)} do
      Logger.info("PPV ticket refunded",
        ticket_id: ticket.id,
        live_event_id: live_event_id,
        org_id: org_id,
        stripe_payment_intent_id: ticket.stripe_payment_intent_id
      )

      :ok
    else
      {:stripe, {:error, :stripe_error, reason}} ->
        Logger.error("Failed to issue Stripe refund for ticket",
          ticket_id: ticket.id,
          live_event_id: live_event_id,
          org_id: org_id,
          reason: inspect(reason)
        )

      {:db, {:error, reason}} ->
        Logger.error("Failed to mark ticket as refunded in DB",
          ticket_id: ticket.id,
          live_event_id: live_event_id,
          org_id: org_id,
          reason: inspect(reason)
        )
    end
  end

  defp issue_stripe_refund(_stripe_client, %LiveEventTicket{stripe_payment_intent_id: nil}) do
    # No payment intent on file — nothing to refund in Stripe
    {:ok, :no_payment_intent}
  end

  defp issue_stripe_refund(stripe_client, %LiveEventTicket{
         stripe_payment_intent_id: payment_intent_id
       }) do
    stripe_client.create_refund(payment_intent_id)
  end

  defp mark_ticket_refunded(ticket, org_id) do
    scope = %Scope{organization: %{id: org_id}}
    Streaming.refund_ticket(scope, ticket)
  end
end
