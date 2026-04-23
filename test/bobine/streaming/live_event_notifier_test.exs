defmodule Bobine.Streaming.LiveEventNotifierTest do
  use Bobine.DataCase, async: true
  use Oban.Testing, repo: Bobine.Repo

  import Swoosh.TestAssertions

  alias Bobine.Streaming.LiveEventNotifier

  describe "send_live_now_emails/2" do
    test "dispatches a NotifyLiveNowWorker and emails all reminder viewers" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "live"
        )

      viewer = insert(:viewer, organization: org, email: "fan@example.com")
      insert(:live_event_reminder, organization: org, live_event: event, viewer: viewer)

      # In test mode Oban runs inline, so the worker fires immediately on insert.
      assert {:ok, _} = LiveEventNotifier.send_live_now_emails(event, org)

      assert_email_sent(subject: ~r/live now/i)
    end
  end

  describe "send_cancellation_emails/2" do
    test "dispatches a NotifyCancellationWorker and emails all reminder viewers" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "canceled"
        )

      viewer = insert(:viewer, organization: org, email: "fan@example.com")
      insert(:live_event_reminder, organization: org, live_event: event, viewer: viewer)

      # In test mode Oban runs inline, so the worker fires immediately on insert.
      assert {:ok, _} = LiveEventNotifier.send_cancellation_emails(event, org)

      assert_email_sent(subject: ~r/canceled/i)
    end
  end

  describe "deliver_live_now/3" do
    test "sends live-now email to viewer" do
      org = insert(:organization, name: "Test Org")

      event =
        insert(:live_event,
          organization: org,
          title: "Big Stream",
          slug: "big-stream"
        )

      viewer = insert(:viewer, organization: org, email: "fan@example.com", display_name: "Fan")

      assert {:ok, email} = LiveEventNotifier.deliver_live_now(viewer, event, org)
      assert email.subject == "[Test Org] Big Stream is live now!"
      assert email.text_body =~ "Big Stream"
      assert email.text_body =~ "Join the stream now"
      assert email.text_body =~ "big-stream"

      assert [{"", "fan@example.com"}] = email.to
    end

    test "uses email as fallback when display_name is nil" do
      org = insert(:organization)

      event = insert(:live_event, organization: org)

      viewer =
        insert(:viewer,
          organization: org,
          email: "anon@example.com",
          display_name: nil
        )

      assert {:ok, email} = LiveEventNotifier.deliver_live_now(viewer, event, org)
      assert email.text_body =~ "anon@example.com"
    end
  end

  describe "deliver_cancellation/3" do
    test "sends cancellation email to viewer" do
      org = insert(:organization, name: "Test Org")

      event =
        insert(:live_event,
          organization: org,
          title: "Big Stream",
          access_type: "subscribers_only"
        )

      viewer = insert(:viewer, organization: org, email: "fan@example.com", display_name: "Fan")

      assert {:ok, email} = LiveEventNotifier.deliver_cancellation(viewer, event, org)
      assert email.subject == "[Test Org] Big Stream has been canceled"
      assert email.text_body =~ "Big Stream"
      assert email.text_body =~ "canceled"
      refute email.text_body =~ "refund"
    end

    test "includes refund note for pay-per-view events" do
      org = insert(:organization, name: "Test Org")

      event =
        insert(:live_event,
          organization: org,
          title: "PPV Stream",
          access_type: "pay_per_view",
          ppv_price_cents: 999
        )

      viewer = insert(:viewer, organization: org, email: "buyer@example.com")

      assert {:ok, email} = LiveEventNotifier.deliver_cancellation(viewer, event, org)
      assert email.text_body =~ "refund"
    end

    test "does not include refund note for non-ppv events" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          access_type: "public"
        )

      viewer = insert(:viewer, organization: org, email: "viewer@example.com")

      assert {:ok, email} = LiveEventNotifier.deliver_cancellation(viewer, event, org)
      refute email.text_body =~ "refund"
    end
  end
end
