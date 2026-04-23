defmodule Bobine.Workers.NotifyLiveNowWorkerTest do
  use Bobine.DataCase, async: true
  use Oban.Testing, repo: Bobine.Repo

  import Swoosh.TestAssertions

  alias Bobine.Repo
  alias Bobine.Streaming.LiveEventReminder
  alias Bobine.Workers.NotifyLiveNowWorker

  describe "perform/1" do
    test "sends live-now emails to all reminder viewers and marks notified_at" do
      org = insert(:organization, name: "Acme TV")
      event = insert(:live_event, organization: org, status: "live", title: "Big Event")
      viewer1 = insert(:viewer, organization: org, email: "v1@example.com")
      viewer2 = insert(:viewer, organization: org, email: "v2@example.com")

      reminder1 =
        insert(:live_event_reminder, organization: org, live_event: event, viewer: viewer1)

      reminder2 =
        insert(:live_event_reminder, organization: org, live_event: event, viewer: viewer2)

      assert {:ok, :sent} =
               perform_job(NotifyLiveNowWorker, %{
                 "live_event_id" => event.id,
                 "organization_id" => org.id
               })

      assert_email_sent(fn email ->
        email.to == [{"", "v1@example.com"}] and
          email.subject =~ "Big Event" and
          email.subject =~ "live now"
      end)

      assert_email_sent(fn email ->
        email.to == [{"", "v2@example.com"}]
      end)

      # Both reminders should be marked as notified
      updated1 = Repo.get!(LiveEventReminder, reminder1.id)
      updated2 = Repo.get!(LiveEventReminder, reminder2.id)
      assert updated1.notified_at != nil
      assert updated2.notified_at != nil
    end

    test "skips sending if event is not live" do
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "scheduled")
      viewer = insert(:viewer, organization: org)

      _reminder =
        insert(:live_event_reminder, organization: org, live_event: event, viewer: viewer)

      assert {:ok, :skipped} =
               perform_job(NotifyLiveNowWorker, %{
                 "live_event_id" => event.id,
                 "organization_id" => org.id
               })

      refute_email_sent()
    end

    test "returns skipped when event does not exist" do
      org = insert(:organization)

      assert {:ok, :skipped} =
               perform_job(NotifyLiveNowWorker, %{
                 "live_event_id" => Ecto.UUID.generate(),
                 "organization_id" => org.id
               })

      refute_email_sent()
    end

    test "returns skipped when organization does not exist" do
      assert {:ok, :skipped} =
               perform_job(NotifyLiveNowWorker, %{
                 "live_event_id" => Ecto.UUID.generate(),
                 "organization_id" => Ecto.UUID.generate()
               })

      refute_email_sent()
    end

    test "returns sent with no emails when event has no reminder viewers" do
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "live")

      assert {:ok, :sent} =
               perform_job(NotifyLiveNowWorker, %{
                 "live_event_id" => event.id,
                 "organization_id" => org.id
               })

      refute_email_sent()
    end

    test "does not re-notify reminders that already have notified_at set" do
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "live")
      viewer = insert(:viewer, organization: org, email: "already@example.com")

      _reminder =
        insert(:live_event_reminder,
          organization: org,
          live_event: event,
          viewer: viewer,
          notified_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      assert {:ok, :sent} =
               perform_job(NotifyLiveNowWorker, %{
                 "live_event_id" => event.id,
                 "organization_id" => org.id
               })

      refute_email_sent()
    end
  end
end
