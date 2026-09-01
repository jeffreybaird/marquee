defmodule Marquee.Workers.NotifyCancellationWorkerTest do
  use Marquee.DataCase, async: true
  use Oban.Testing, repo: Marquee.Repo

  import Swoosh.TestAssertions

  alias Marquee.Workers.NotifyCancellationWorker

  describe "perform/1 — non-PPV events" do
    test "sends cancellation emails only to reminder viewers" do
      org = insert(:organization, name: "Acme TV")

      event =
        insert(:live_event,
          organization: org,
          status: "canceled",
          title: "Weekend Show",
          access_type: "subscribers_only"
        )

      viewer1 = insert(:viewer, organization: org, email: "fan1@example.com")
      viewer2 = insert(:viewer, organization: org, email: "fan2@example.com")
      _non_reminder_viewer = insert(:viewer, organization: org, email: "other@example.com")

      insert(:live_event_reminder, organization: org, live_event: event, viewer: viewer1)
      insert(:live_event_reminder, organization: org, live_event: event, viewer: viewer2)

      assert {:ok, :sent} =
               perform_job(NotifyCancellationWorker, %{
                 "live_event_id" => event.id,
                 "organization_id" => org.id
               })

      assert_email_sent(fn email ->
        email.to == [{"", "fan1@example.com"}] and
          email.subject =~ "Weekend Show" and
          email.subject =~ "canceled"
      end)

      assert_email_sent(fn email ->
        email.to == [{"", "fan2@example.com"}]
      end)

      # No additional emails beyond the 2 reminder viewers
      assert_no_email_sent()
    end

    test "returns sent with no emails when no reminder viewers" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "canceled",
          access_type: "public"
        )

      assert {:ok, :sent} =
               perform_job(NotifyCancellationWorker, %{
                 "live_event_id" => event.id,
                 "organization_id" => org.id
               })

      refute_email_sent()
    end
  end

  describe "perform/1 — PPV events" do
    test "sends to ticket holders and reminder viewers" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "canceled",
          access_type: "pay_per_view",
          ppv_price_cents: 999
        )

      ticket_only_viewer = insert(:viewer, organization: org, email: "ticket@example.com")
      reminder_only_viewer = insert(:viewer, organization: org, email: "reminder@example.com")

      insert(:live_event_ticket,
        organization: org,
        live_event: event,
        viewer: ticket_only_viewer
      )

      insert(:live_event_reminder,
        organization: org,
        live_event: event,
        viewer: reminder_only_viewer
      )

      assert {:ok, :sent} =
               perform_job(NotifyCancellationWorker, %{
                 "live_event_id" => event.id,
                 "organization_id" => org.id
               })

      assert_email_sent(fn email ->
        email.to == [{"", "ticket@example.com"}] and email.text_body =~ "refund"
      end)

      assert_email_sent(fn email ->
        email.to == [{"", "reminder@example.com"}]
      end)
    end

    test "deduplicates viewers with both a ticket and a reminder" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "canceled",
          access_type: "pay_per_view",
          ppv_price_cents: 999
        )

      viewer = insert(:viewer, organization: org, email: "both@example.com")

      insert(:live_event_ticket,
        organization: org,
        live_event: event,
        viewer: viewer
      )

      insert(:live_event_reminder,
        organization: org,
        live_event: event,
        viewer: viewer
      )

      assert {:ok, :sent} =
               perform_job(NotifyCancellationWorker, %{
                 "live_event_id" => event.id,
                 "organization_id" => org.id
               })

      # Only one email should be sent despite both ticket and reminder
      assert_email_sent(fn email -> email.to == [{"", "both@example.com"}] end)
      assert_no_email_sent()
    end

    test "does not notify viewers with refunded tickets" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "canceled",
          access_type: "pay_per_view",
          ppv_price_cents: 999
        )

      refunded_viewer = insert(:viewer, organization: org, email: "refunded@example.com")

      insert(:live_event_ticket,
        organization: org,
        live_event: event,
        viewer: refunded_viewer,
        refunded_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      assert {:ok, :sent} =
               perform_job(NotifyCancellationWorker, %{
                 "live_event_id" => event.id,
                 "organization_id" => org.id
               })

      refute_email_sent()
    end
  end

  describe "perform/1 — missing records" do
    test "returns skipped when event does not exist" do
      org = insert(:organization)

      assert {:ok, :skipped} =
               perform_job(NotifyCancellationWorker, %{
                 "live_event_id" => Ecto.UUID.generate(),
                 "organization_id" => org.id
               })

      refute_email_sent()
    end

    test "returns skipped when organization does not exist" do
      assert {:ok, :skipped} =
               perform_job(NotifyCancellationWorker, %{
                 "live_event_id" => Ecto.UUID.generate(),
                 "organization_id" => Ecto.UUID.generate()
               })

      refute_email_sent()
    end
  end
end
