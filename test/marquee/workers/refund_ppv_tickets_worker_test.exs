defmodule Marquee.Workers.RefundPpvTicketsWorkerTest do
  use Marquee.DataCase, async: true
  use Oban.Testing, repo: Marquee.Repo

  import Mox

  alias Marquee.Repo
  alias Marquee.Streaming.LiveEventTicket
  alias Marquee.Workers.RefundPpvTicketsWorker

  setup :verify_on_exit!

  defp ppv_event(org) do
    insert(:live_event,
      organization: org,
      access_type: "pay_per_view",
      ppv_price_cents: 999
    )
  end

  defp ticket_with_payment_intent(event, viewer, payment_intent_id) do
    insert(:live_event_ticket,
      organization: event.organization,
      live_event: event,
      viewer: viewer,
      stripe_payment_intent_id: payment_intent_id,
      amount_cents: 999
    )
  end

  defp ticket_already_refunded(event, viewer) do
    insert(:live_event_ticket,
      organization: event.organization,
      live_event: event,
      viewer: viewer,
      stripe_payment_intent_id: "pi_already_refunded",
      amount_cents: 999,
      refunded_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end

  describe "perform/1" do
    test "refunds all non-refunded tickets for the event" do
      org = insert(:organization)
      event = ppv_event(org)
      viewer1 = insert(:viewer, organization: org)
      viewer2 = insert(:viewer, organization: org)

      t1 = ticket_with_payment_intent(event, viewer1, "pi_1111")
      t2 = ticket_with_payment_intent(event, viewer2, "pi_2222")

      # The worker fetches tickets without an ORDER BY, so it may refund t2
      # before t1. Two separate ordered `expect`s would force pi_1111 to be the
      # first call and flake when the order differs; a single count-2
      # expectation with a clause per payment intent asserts exactly two refunds
      # with the right ids, order-independently.
      expect(Marquee.Billing.MockStripeClient, :create_refund, 2, fn
        "pi_1111", _opts -> {:ok, %{id: "re_1111"}}
        "pi_2222", _opts -> {:ok, %{id: "re_2222"}}
      end)

      assert :ok =
               perform_job(RefundPpvTicketsWorker, %{
                 "live_event_id" => event.id,
                 "organization_id" => org.id
               })

      assert Repo.get!(LiveEventTicket, t1.id).refunded_at != nil
      assert Repo.get!(LiveEventTicket, t2.id).refunded_at != nil
    end

    test "skips already-refunded tickets" do
      org = insert(:organization)
      event = ppv_event(org)
      viewer = insert(:viewer, organization: org)
      already_refunded = ticket_already_refunded(event, viewer)

      # No Stripe calls expected because there's nothing to refund
      assert :ok =
               perform_job(RefundPpvTicketsWorker, %{
                 "live_event_id" => event.id,
                 "organization_id" => org.id
               })

      # refunded_at was already set — should remain unchanged
      ticket = Repo.get!(LiveEventTicket, already_refunded.id)
      assert ticket.refunded_at == already_refunded.refunded_at
    end

    test "continues processing remaining tickets when one Stripe refund fails" do
      org = insert(:organization)
      event = ppv_event(org)
      viewer1 = insert(:viewer, organization: org)
      viewer2 = insert(:viewer, organization: org)

      _t1 = ticket_with_payment_intent(event, viewer1, "pi_fail")
      t2 = ticket_with_payment_intent(event, viewer2, "pi_ok")

      stub(Marquee.Billing.MockStripeClient, :create_refund, fn
        "pi_fail", _opts -> {:error, :stripe_error, %{message: "card_error"}}
        "pi_ok", _opts -> {:ok, %{id: "re_ok"}}
      end)

      assert :ok =
               perform_job(RefundPpvTicketsWorker, %{
                 "live_event_id" => event.id,
                 "organization_id" => org.id
               })

      # The successful ticket should be marked refunded
      assert Repo.get!(LiveEventTicket, t2.id).refunded_at != nil
    end

    test "handles tickets with no payment intent without calling Stripe" do
      org = insert(:organization)
      event = ppv_event(org)
      viewer = insert(:viewer, organization: org)

      ticket =
        insert(:live_event_ticket,
          organization: org,
          live_event: event,
          viewer: viewer,
          stripe_payment_intent_id: nil,
          amount_cents: 0
        )

      # No Stripe call expected
      assert :ok =
               perform_job(RefundPpvTicketsWorker, %{
                 "live_event_id" => event.id,
                 "organization_id" => org.id
               })

      assert Repo.get!(LiveEventTicket, ticket.id).refunded_at != nil
    end
  end
end
