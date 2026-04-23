defmodule Bobine.StreamingTest do
  use Bobine.DataCase, async: true

  import Bobine.Factory
  import Mox

  alias Bobine.Accounts.Scope
  alias Bobine.Content.MockMuxClient
  alias Bobine.Streaming

  setup :verify_on_exit!

  defp build_scope(org, user \\ nil) do
    user = user || insert(:user)
    %Scope{user: user, organization: org}
  end

  ## ---------------------------------------------------------------------------
  ## list_live_events/2
  ## ---------------------------------------------------------------------------

  describe "list_live_events/2" do
    test "returns paginated events for org" do
      org = insert(:organization)
      insert(:live_event, organization: org)
      insert(:live_event, organization: org)

      result = Streaming.list_live_events(org)
      assert result.total == 2
      assert length(result.results) == 2
    end

    test "excludes soft-deleted events" do
      org = insert(:organization)
      insert(:live_event, organization: org)
      insert(:live_event, organization: org, deleted_at: DateTime.utc_now())

      result = Streaming.list_live_events(org)
      assert result.total == 1
    end

    test "filters by status" do
      org = insert(:organization)
      insert(:live_event, organization: org, status: "scheduled")
      insert(:live_event, organization: org, status: "live")

      result = Streaming.list_live_events(org, status: "live")
      assert result.total == 1
      assert hd(result.results).status == "live"
    end

    test "does not return events from other orgs" do
      org = insert(:organization)
      other_org = insert(:organization)
      insert(:live_event, organization: other_org)

      result = Streaming.list_live_events(org)
      assert result.total == 0
    end
  end

  ## ---------------------------------------------------------------------------
  ## get_live_event/2
  ## ---------------------------------------------------------------------------

  describe "get_live_event/2" do
    test "returns event within org" do
      org = insert(:organization)
      event = insert(:live_event, organization: org)

      assert {:ok, found} = Streaming.get_live_event(org, event.id)
      assert found.id == event.id
    end

    test "returns not_found for wrong org" do
      org = insert(:organization)
      other_org = insert(:organization)
      event = insert(:live_event, organization: other_org)

      assert {:error, :not_found} = Streaming.get_live_event(org, event.id)
    end
  end

  ## ---------------------------------------------------------------------------
  ## get_live_event_by_slug/2
  ## ---------------------------------------------------------------------------

  describe "get_live_event_by_slug/2" do
    test "returns event by slug within org" do
      org = insert(:organization)
      event = insert(:live_event, organization: org, slug: "my-event")

      assert {:ok, found} = Streaming.get_live_event_by_slug(org, "my-event")
      assert found.id == event.id
    end

    test "returns not_found for slug in other org" do
      org = insert(:organization)
      other_org = insert(:organization)
      insert(:live_event, organization: other_org, slug: "my-event")

      assert {:error, :not_found} = Streaming.get_live_event_by_slug(org, "my-event")
    end
  end

  ## ---------------------------------------------------------------------------
  ## get_live_event_by_mux_stream_id/1
  ## ---------------------------------------------------------------------------

  describe "get_live_event_by_mux_stream_id/1" do
    test "returns event by mux stream id" do
      event = insert(:live_event, mux_live_stream_id: "stream_abc")

      assert {:ok, found} = Streaming.get_live_event_by_mux_stream_id("stream_abc")
      assert found.id == event.id
    end

    test "returns not_found for unknown stream id" do
      assert {:error, :not_found} = Streaming.get_live_event_by_mux_stream_id("unknown_stream")
    end
  end

  ## ---------------------------------------------------------------------------
  ## create_live_event/2
  ## ---------------------------------------------------------------------------

  describe "create_live_event/2" do
    test "creates event and provisions Mux live stream" do
      org = insert(:organization)
      scope = build_scope(org)

      expect(MockMuxClient, :create_live_stream, fn _params ->
        {:ok,
         %{
           "id" => "mux_stream_001",
           "playback_ids" => [%{"id" => "pb_001", "policy" => "public"}],
           "stream_key" => "sk_001"
         }}
      end)

      attrs = %{
        title: "My Stream",
        slug: "my-stream",
        scheduled_start_at: ~U[2026-06-01 18:00:00Z],
        access_type: "subscribers_only",
        organization_id: org.id
      }

      assert {:ok, event} = Streaming.create_live_event(scope, attrs)
      assert event.title == "My Stream"
      assert event.mux_live_stream_id == "mux_stream_001"
      assert event.mux_live_playback_id == "pb_001"
      assert event.organization_id == org.id
    end

    test "rolls back DB record when Mux API fails" do
      org = insert(:organization)
      scope = build_scope(org)

      expect(MockMuxClient, :create_live_stream, fn _params ->
        {:error, :mux_error, %{type: "api_error", messages: ["quota exceeded"]}}
      end)

      attrs = %{
        title: "Failed Stream",
        slug: "failed-stream",
        scheduled_start_at: ~U[2026-06-01 18:00:00Z],
        access_type: "subscribers_only",
        organization_id: org.id
      }

      assert {:error, :mux_error, _details} = Streaming.create_live_event(scope, attrs)

      # DB record should not exist
      result = Streaming.list_live_events(org)
      assert result.total == 0
    end

    test "returns validation error for invalid attrs" do
      org = insert(:organization)
      scope = build_scope(org)

      assert {:error, :validation, _changeset} =
               Streaming.create_live_event(scope, %{organization_id: org.id})
    end
  end

  ## ---------------------------------------------------------------------------
  ## update_live_event/3
  ## ---------------------------------------------------------------------------

  describe "update_live_event/3" do
    test "updates event attributes" do
      org = insert(:organization)
      scope = build_scope(org)
      event = insert(:live_event, organization: org, title: "Old Title")

      assert {:ok, updated} = Streaming.update_live_event(scope, event, %{title: "New Title"})
      assert updated.title == "New Title"
    end

    test "returns validation error for invalid attrs" do
      org = insert(:organization)
      scope = build_scope(org)
      event = insert(:live_event, organization: org)

      assert {:error, :validation, _cs} =
               Streaming.update_live_event(scope, event, %{access_type: "invalid"})
    end
  end

  ## ---------------------------------------------------------------------------
  ## transition_event/3
  ## ---------------------------------------------------------------------------

  describe "transition_event/3" do
    test "valid transition succeeds" do
      org = insert(:organization)
      scope = build_scope(org)
      event = insert(:live_event, organization: org, status: "draft")

      assert {:ok, updated} = Streaming.transition_event(scope, event, "scheduled")
      assert updated.status == "scheduled"
    end

    test "invalid transition returns error" do
      org = insert(:organization)
      scope = build_scope(org)
      event = insert(:live_event, organization: org, status: "ended")

      assert {:error, :invalid_transition} = Streaming.transition_event(scope, event, "live")
    end

    test "transitioning to live sets went_live_at" do
      org = insert(:organization)
      scope = build_scope(org)
      event = insert(:live_event, organization: org, status: "scheduled")

      assert {:ok, updated} = Streaming.transition_event(scope, event, "live")
      assert updated.went_live_at != nil
    end

    test "transitioning to ended sets ended_at" do
      org = insert(:organization)
      scope = build_scope(org)
      event = insert(:live_event, organization: org, status: "live")

      assert {:ok, updated} = Streaming.transition_event(scope, event, "ended")
      assert updated.ended_at != nil
    end

    test "transitioning to canceled sets canceled_at" do
      org = insert(:organization)
      scope = build_scope(org)
      event = insert(:live_event, organization: org, status: "scheduled")

      assert {:ok, updated} = Streaming.transition_event(scope, event, "canceled")
      assert updated.canceled_at != nil
    end
  end

  ## ---------------------------------------------------------------------------
  ## cancel_live_event/2
  ## ---------------------------------------------------------------------------

  describe "cancel_live_event/2" do
    test "transitions event to canceled from scheduled" do
      org = insert(:organization)
      scope = build_scope(org)
      event = insert(:live_event, organization: org, status: "scheduled")

      assert {:ok, canceled} = Streaming.cancel_live_event(scope, event)
      assert canceled.status == "canceled"
    end

    test "cannot cancel an ended event" do
      org = insert(:organization)
      scope = build_scope(org)
      event = insert(:live_event, organization: org, status: "ended")

      assert {:error, :invalid_transition} = Streaming.cancel_live_event(scope, event)
    end
  end

  ## ---------------------------------------------------------------------------
  ## can_watch_event?/2
  ## ---------------------------------------------------------------------------

  describe "can_watch_event?/2" do
    test "public event: always true including nil viewer" do
      event = build(:live_event, access_type: "public")
      assert Streaming.can_watch_event?(event, nil)
      assert Streaming.can_watch_event?(event, build(:viewer))
    end

    test "subscribers_only: active viewer can watch" do
      event = build(:live_event, access_type: "subscribers_only")
      viewer = build(:viewer, subscription_status: "active")
      assert Streaming.can_watch_event?(event, viewer)
    end

    test "subscribers_only: trial viewer can watch" do
      event = build(:live_event, access_type: "subscribers_only")
      viewer = build(:viewer, subscription_status: "trial")
      assert Streaming.can_watch_event?(event, viewer)
    end

    test "subscribers_only: past_due viewer can watch" do
      event = build(:live_event, access_type: "subscribers_only")
      viewer = build(:viewer, subscription_status: "past_due")
      assert Streaming.can_watch_event?(event, viewer)
    end

    test "subscribers_only: canceled viewer cannot watch" do
      event = build(:live_event, access_type: "subscribers_only")
      viewer = build(:viewer, subscription_status: "canceled")
      refute Streaming.can_watch_event?(event, viewer)
    end

    test "subscribers_only: none viewer cannot watch" do
      event = build(:live_event, access_type: "subscribers_only")
      viewer = build(:viewer, subscription_status: "none")
      refute Streaming.can_watch_event?(event, viewer)
    end

    test "subscribers_only: nil viewer cannot watch" do
      event = build(:live_event, access_type: "subscribers_only")
      refute Streaming.can_watch_event?(event, nil)
    end

    test "pay_per_view: nil viewer cannot watch" do
      event = insert(:live_event, access_type: "pay_per_view")
      refute Streaming.can_watch_event?(event, nil)
    end

    test "pay_per_view: viewer with valid ticket can watch" do
      org = insert(:organization)
      event = insert(:live_event, organization: org, access_type: "pay_per_view", status: "live")
      viewer = insert(:viewer, organization: org)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert(:live_event_ticket,
        organization: org,
        live_event: event,
        viewer: viewer,
        access_starts_at: now,
        access_ends_at: DateTime.add(now, 3600, :second)
      )

      assert Streaming.can_watch_event?(event, viewer)
    end

    test "pay_per_view: viewer with expired ticket cannot watch" do
      org = insert(:organization)
      event = insert(:live_event, organization: org, access_type: "pay_per_view")
      viewer = insert(:viewer, organization: org)
      past = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)

      insert(:live_event_ticket,
        organization: org,
        live_event: event,
        viewer: viewer,
        access_starts_at: DateTime.add(past, -7200, :second),
        access_ends_at: past
      )

      refute Streaming.can_watch_event?(event, viewer)
    end
  end

  ## ---------------------------------------------------------------------------
  ## check_event_access/2
  ## ---------------------------------------------------------------------------

  describe "check_event_access/2" do
    test "public always allowed" do
      event = build(:live_event, access_type: "public")
      assert {:ok, :allowed} = Streaming.check_event_access(event, nil)
    end

    test "subscribers_only with no viewer returns no_subscription" do
      event = build(:live_event, access_type: "subscribers_only")
      assert {:error, :access_denied, :no_subscription} = Streaming.check_event_access(event, nil)
    end

    test "subscribers_only with canceled viewer returns no_subscription" do
      event = build(:live_event, access_type: "subscribers_only")
      viewer = build(:viewer, subscription_status: "canceled")

      assert {:error, :access_denied, :no_subscription} =
               Streaming.check_event_access(event, viewer)
    end

    test "pay_per_view with no viewer returns no_ticket" do
      event = insert(:live_event, access_type: "pay_per_view")
      assert {:error, :access_denied, :no_ticket} = Streaming.check_event_access(event, nil)
    end

    test "pay_per_view with no ticket returns no_ticket" do
      org = insert(:organization)
      event = insert(:live_event, organization: org, access_type: "pay_per_view")
      viewer = insert(:viewer, organization: org)

      assert {:error, :access_denied, :no_ticket} = Streaming.check_event_access(event, viewer)
    end

    test "pay_per_view with expired ticket returns ticket_expired" do
      org = insert(:organization)
      event = insert(:live_event, organization: org, access_type: "pay_per_view")
      viewer = insert(:viewer, organization: org)
      past = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)

      insert(:live_event_ticket,
        organization: org,
        live_event: event,
        viewer: viewer,
        access_starts_at: DateTime.add(past, -7200, :second),
        access_ends_at: past
      )

      assert {:error, :access_denied, :ticket_expired} =
               Streaming.check_event_access(event, viewer)
    end
  end

  ## ---------------------------------------------------------------------------
  ## PPV access window calculation
  ## ---------------------------------------------------------------------------

  describe "create_ticket/3 access window" do
    test "access_starts_at is now when event has already started" do
      org = insert(:organization)
      past_start = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)

      event =
        insert(:live_event,
          organization: org,
          access_type: "pay_per_view",
          ppv_price_cents: 999,
          ppv_access_window_hours: 24,
          scheduled_start_at: past_start,
          status: "live"
        )

      viewer = insert(:viewer, organization: org)

      assert {:ok, ticket} =
               Streaming.create_ticket(event, viewer, %{
                 amount_cents: 999,
                 stripe_payment_intent_id: "pi_test"
               })

      # access_starts_at should be approximately now (within a few seconds)
      now = DateTime.utc_now()
      diff = DateTime.diff(now, ticket.access_starts_at, :second)
      assert diff >= 0 and diff < 5
    end

    test "access_starts_at is event start when event hasn't started yet" do
      org = insert(:organization)
      future_start = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)

      event =
        insert(:live_event,
          organization: org,
          access_type: "pay_per_view",
          ppv_price_cents: 999,
          ppv_access_window_hours: 48,
          scheduled_start_at: future_start
        )

      viewer = insert(:viewer, organization: org)

      assert {:ok, ticket} = Streaming.create_ticket(event, viewer, %{amount_cents: 999})
      assert ticket.access_starts_at == future_start

      expected_ends_at = DateTime.add(future_start, 48 * 3600, :second)
      assert ticket.access_ends_at == expected_ends_at
    end
  end

  ## ---------------------------------------------------------------------------
  ## Chat
  ## ---------------------------------------------------------------------------

  describe "post_chat_message/3" do
    test "viewer with access can post message to live event" do
      org = insert(:organization)
      event = insert(:live_event, organization: org, access_type: "public", status: "live")
      viewer = insert(:viewer, organization: org)

      assert {:ok, msg} = Streaming.post_chat_message(event, viewer, "Hello!")
      assert msg.content == "Hello!"
    end

    test "cannot post to non-live event" do
      org = insert(:organization)
      event = insert(:live_event, organization: org, access_type: "public", status: "scheduled")
      viewer = insert(:viewer, organization: org)

      assert {:error, :event_not_live} = Streaming.post_chat_message(event, viewer, "Hello!")
    end

    test "banned viewer cannot post" do
      org = insert(:organization)
      event = insert(:live_event, organization: org, access_type: "public", status: "live")
      viewer = insert(:viewer, organization: org)
      user = insert(:user)
      scope = %Scope{user: user, organization: org}

      :ok = Streaming.ban_viewer_from_chat(scope, event, viewer)

      assert {:error, :access_denied, :viewer_banned} =
               Streaming.post_chat_message(event, viewer, "Hello!")
    end

    test "returns validation error for message over 500 chars" do
      org = insert(:organization)
      event = insert(:live_event, organization: org, access_type: "public", status: "live")
      viewer = insert(:viewer, organization: org)
      long_content = String.duplicate("a", 501)

      assert {:error, :validation, changeset} =
               Streaming.post_chat_message(event, viewer, long_content)

      assert "should be at most 500 character(s)" in errors_on(changeset).content
    end

    test "subscribers_only: unsubscribed viewer denied" do
      org = insert(:organization)

      event =
        insert(:live_event, organization: org, access_type: "subscribers_only", status: "live")

      viewer = insert(:viewer, organization: org, subscription_status: "none")

      assert {:error, :access_denied, :no_subscription} =
               Streaming.post_chat_message(event, viewer, "Hi")
    end
  end

  ## ---------------------------------------------------------------------------
  ## ban_viewer_from_chat/3
  ## ---------------------------------------------------------------------------

  describe "ban_viewer_from_chat/3" do
    test "banning a viewer succeeds" do
      org = insert(:organization)
      event = insert(:live_event, organization: org)
      viewer = insert(:viewer, organization: org)
      user = insert(:user)
      scope = %Scope{user: user, organization: org}

      assert :ok = Streaming.ban_viewer_from_chat(scope, event, viewer)
      assert Streaming.viewer_banned?(event, viewer)
    end

    test "banning same viewer twice returns already_banned" do
      org = insert(:organization)
      event = insert(:live_event, organization: org)
      viewer = insert(:viewer, organization: org)
      user = insert(:user)
      scope = %Scope{user: user, organization: org}

      :ok = Streaming.ban_viewer_from_chat(scope, event, viewer)

      assert {:error, :already_banned} = Streaming.ban_viewer_from_chat(scope, event, viewer)
    end
  end

  ## ---------------------------------------------------------------------------
  ## Reminders
  ## ---------------------------------------------------------------------------

  describe "add_reminder/2 and remove_reminder/2" do
    test "adds reminder for viewer" do
      org = insert(:organization)
      event = insert(:live_event, organization: org)
      viewer = insert(:viewer, organization: org)

      assert {:ok, _reminder} = Streaming.add_reminder(event, viewer)
      assert Streaming.has_reminder?(event, viewer)
    end

    test "adding reminder twice returns already_set" do
      org = insert(:organization)
      event = insert(:live_event, organization: org)
      viewer = insert(:viewer, organization: org)

      {:ok, _} = Streaming.add_reminder(event, viewer)
      assert {:error, :already_set} = Streaming.add_reminder(event, viewer)
    end

    test "removes reminder" do
      org = insert(:organization)
      event = insert(:live_event, organization: org)
      viewer = insert(:viewer, organization: org)

      {:ok, _} = Streaming.add_reminder(event, viewer)
      :ok = Streaming.remove_reminder(event, viewer)
      refute Streaming.has_reminder?(event, viewer)
    end
  end

  ## ---------------------------------------------------------------------------
  ## delete_live_event/2
  ## ---------------------------------------------------------------------------

  describe "delete_live_event/2" do
    test "soft-deletes event" do
      org = insert(:organization)
      scope = build_scope(org)
      event = insert(:live_event, organization: org)

      expect(MockMuxClient, :delete_live_stream, fn _stream_id -> :ok end)

      assert {:ok, deleted} = Streaming.delete_live_event(scope, event)
      assert deleted.deleted_at != nil

      # Should not appear in list
      result = Streaming.list_live_events(org)
      assert result.total == 0
    end
  end
end
