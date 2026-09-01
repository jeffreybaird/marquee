defmodule MarqueeWeb.Viewer.LiveEventWatchLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Streaming.ChatRateLimiter

  # ---------------------------------------------------------------------------
  # scheduled event
  # ---------------------------------------------------------------------------

  describe "/events/:slug — scheduled event" do
    test "shows countdown info and reminder button for unauthenticated visitor", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          title: "Big Premiere",
          slug: "big-premiere",
          scheduled_start_at:
            DateTime.utc_now() |> DateTime.add(7200) |> DateTime.truncate(:second)
        )

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ "Big Premiere"
      assert html =~ ~s(data-test="event-scheduled")
      assert html =~ ~s(data-test="reminder-toggle")
      assert html =~ ~s(data-test="ics-download")
      assert html =~ ~s(data-test="google-calendar-link")
    end

    test "shows reminder button for authenticated viewer", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      event = insert(:live_event, organization: org, status: "scheduled", slug: "upcoming-show")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="reminder-toggle")
    end

    test "toggle_reminder sets reminder for authenticated viewer", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      event = insert(:live_event, organization: org, status: "scheduled", slug: "toggle-test")

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/events/#{event.slug}")

      # Add reminder
      html = render_click(view, "toggle_reminder")
      assert html =~ "Remove reminder"

      # Remove reminder
      html = render_click(view, "toggle_reminder")
      assert html =~ "Remind me"
    end

    test "toggle_reminder redirects unauthenticated viewer to login", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event, organization: org, status: "scheduled", slug: "no-auth-reminder")

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      assert {:error, {:live_redirect, %{to: "/login"}}} =
               render_click(view, "toggle_reminder")
    end

    test "ICS download link points to calendar.ics endpoint", %{conn: conn} do
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "scheduled", slug: "ics-link-test")

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ "/events/ics-link-test/calendar.ics"
    end
  end

  # ---------------------------------------------------------------------------
  # live event (public access)
  # ---------------------------------------------------------------------------

  describe "/events/:slug — live event (public)" do
    test "shows live player for public event without viewer", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "public-stream",
          access_type: "public",
          mux_live_playback_id: "live_playback_123"
        )

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="event-live")
      assert html =~ ~s(data-test="sv-live-player")
      assert html =~ "live_playback_123"
    end

    test "shows live player for subscribers-only event with active viewer", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "active")

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "sub-only-stream",
          access_type: "subscribers_only",
          mux_live_playback_id: "live_pb_sub"
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="sv-live-player")
      assert html =~ "live_pb_sub"
    end

    test "shows subscription gate for subscribers-only event with no viewer", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "gate-test",
          access_type: "subscribers_only"
        )

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="access-denied-subscription")
      refute html =~ ~s(data-test="sv-live-player")
    end

    test "shows subscription gate for unsubscribed viewer", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "gate-unsubscribed",
          access_type: "subscribers_only"
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="access-denied-subscription")
    end

    test "shows PPV gate for pay_per_view event with no ticket", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "ppv-no-ticket",
          access_type: "pay_per_view",
          ppv_price_cents: 999
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="access-denied-ticket")
      refute html =~ ~s(data-test="sv-live-player")
    end
  end

  # ---------------------------------------------------------------------------
  # ended event
  # ---------------------------------------------------------------------------

  describe "/events/:slug — ended event" do
    test "shows ended notice", %{conn: conn} do
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "ended", slug: "ended-show")

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="event-ended")
      assert html =~ "This event has ended"
    end

    test "shows no-recording message when no recording attached", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "ended",
          slug: "no-recording"
        )

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="no-recording")
    end
  end

  # ---------------------------------------------------------------------------
  # canceled / did_not_occur
  # ---------------------------------------------------------------------------

  describe "/events/:slug — canceled event" do
    test "shows canceled notice", %{conn: conn} do
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "canceled", slug: "canceled-show")

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="event-canceled")
      assert html =~ "has been canceled"
    end

    test "shows did-not-occur notice", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event, organization: org, status: "did_not_occur", slug: "did-not-occur")

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="event-canceled")
      assert html =~ "did not occur"
    end
  end

  # ---------------------------------------------------------------------------
  # draft event — redirect
  # ---------------------------------------------------------------------------

  describe "/events/:slug — draft event" do
    test "redirects to /events for draft event", %{conn: conn} do
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "draft", slug: "secret-draft")

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")

      assert {:error, {:live_redirect, %{to: "/events"}}} =
               live(conn, ~p"/events/#{event.slug}")
    end
  end

  # ---------------------------------------------------------------------------
  # not found
  # ---------------------------------------------------------------------------

  describe "/events/:slug — not found" do
    test "redirects to /events for unknown slug", %{conn: conn} do
      org = insert(:organization)

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")

      assert {:error, {:live_redirect, %{to: "/events"}}} =
               live(conn, ~p"/events/no-such-event")
    end
  end

  # ---------------------------------------------------------------------------
  # chat island
  # ---------------------------------------------------------------------------

  describe "live chat" do
    setup do
      ChatRateLimiter.clear()
      :ok
    end

    test "chat section renders for live event with valid subscriber access", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "active")

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "chat-live-test",
          access_type: "subscribers_only",
          mux_live_playback_id: "live_pb_chat"
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="chat-section")
      assert html =~ ~s(data-test="chat-input-area")
      assert html =~ ~s(data-test="chat-form")
    end

    test "chat input not shown for scheduled event", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          slug: "chat-scheduled-test"
        )

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}")

      refute html =~ ~s(data-test="chat-section")
      refute html =~ ~s(data-test="chat-input-area")
    end

    test "chat input not shown for live event with no viewer (unauthenticated)", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "chat-no-auth-test",
          access_type: "subscribers_only",
          mux_live_playback_id: "live_pb_no_auth"
        )

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="chat-section")
      refute html =~ ~s(data-test="chat-input-area")
      assert html =~ ~s(data-test="chat-login-prompt")
    end

    test "chat shows access-denied message for logged-in viewer without subscription", %{
      conn: _conn
    } do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "chat-no-access-test",
          access_type: "subscribers_only",
          mux_live_playback_id: "live_pb_no_access"
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="chat-section")
      refute html =~ ~s(data-test="chat-input-area")
      assert html =~ ~s(data-test="chat-access-denied")
    end

    test "viewer sends a chat message and it appears via PubSub stream", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "active")

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "chat-send-test",
          access_type: "subscribers_only",
          mux_live_playback_id: "live_pb_send"
        )

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/events/#{event.slug}")

      view
      |> form(~s([data-test="chat-form"]), message: "Hello chat!")
      |> render_submit()

      # Message is broadcast via PubSub — simulate it arriving
      {:ok, msg} = Marquee.Streaming.post_chat_message(event, viewer, "Hello from PubSub!")

      send(
        view.pid,
        {:marquee_event, {:chat_message_posted, msg}, %{organization: org}}
      )

      html = render(view)
      assert html =~ "Hello from PubSub!"
    end

    test "rate-limited message shows error flash", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "active")

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "chat-rate-limit-test",
          access_type: "subscribers_only",
          mux_live_playback_id: "live_pb_rate"
        )

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/events/#{event.slug}")

      # First submit fills the rate limiter slot
      view
      |> form(~s([data-test="chat-form"]), message: "First message")
      |> render_submit()

      # Second submit within burst window hits rate limit
      html =
        view
        |> form(~s([data-test="chat-form"]), message: "Too fast!")
        |> render_submit()

      assert html =~ "Slow down"
    end

    test "banned notice appears when viewer_banned_from_chat event received via PubSub", %{
      conn: _conn
    } do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "active")

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "chat-ban-pubsub-test",
          access_type: "subscribers_only",
          mux_live_playback_id: "live_pb_ban"
        )

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="chat-input-area")
      refute html =~ ~s(data-test="chat-banned-notice")

      send(
        view.pid,
        {:marquee_event, {:viewer_banned_from_chat, %{event: event, viewer: viewer}},
         %{organization: org}}
      )

      html = render(view)
      assert html =~ ~s(data-test="chat-banned-notice")
      refute html =~ ~s(data-test="chat-input-area")
    end

    test "real-time message appears via PubSub chat_message_posted broadcast", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      other_viewer = insert(:viewer, organization: org, subscription_status: "active")

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "chat-realtime-test",
          access_type: "subscribers_only",
          mux_live_playback_id: "live_pb_realtime"
        )

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/events/#{event.slug}")

      refute html =~ "realtime-message-content"

      {:ok, msg} =
        Marquee.Streaming.post_chat_message(event, other_viewer, "realtime-message-content")

      send(
        view.pid,
        {:marquee_event, {:chat_message_posted, msg}, %{organization: org}}
      )

      html = render(view)
      assert html =~ "realtime-message-content"
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub status transition
  # ---------------------------------------------------------------------------

  describe "real-time status transition via PubSub" do
    test "scheduled → live transition renders player", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          slug: "going-live",
          access_type: "public",
          mux_live_playback_id: "live_pb_transition"
        )

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="event-scheduled")
      refute html =~ ~s(data-test="event-live")

      # Simulate Mux/operator triggering status change
      updated = %{event | status: "live"}

      send(
        view.pid,
        {:marquee_event, {:live_event_status_changed, updated}, %{organization: org}}
      )

      html = render(view)
      assert html =~ ~s(data-test="event-live")
      assert html =~ ~s(data-test="sv-live-player")
    end

    test "live → ended transition hides player", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "wrapping-up",
          access_type: "public",
          mux_live_playback_id: "live_pb_end"
        )

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="event-live")

      updated = %{event | status: "ended", recording_video_id: nil}

      send(
        view.pid,
        {:marquee_event, {:live_event_status_changed, updated}, %{organization: org}}
      )

      html = render(view)
      assert html =~ ~s(data-test="event-ended")
      refute html =~ ~s(data-test="sv-live-player")
    end

    test "ignores PubSub events for different events", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          slug: "my-event",
          access_type: "public"
        )

      other_event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          slug: "other-event",
          access_type: "public"
        )

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ ~s(data-test="event-scheduled")

      # Send update for the OTHER event
      updated_other = %{other_event | status: "live"}

      send(
        view.pid,
        {:marquee_event, {:live_event_status_changed, updated_other}, %{organization: org}}
      )

      html = render(view)
      # My event should still show scheduled
      assert html =~ ~s(data-test="event-scheduled")
      refute html =~ ~s(data-test="event-live")
    end
  end

  # ---------------------------------------------------------------------------
  # layout / chat drawer
  # ---------------------------------------------------------------------------

  describe "live event layout" do
    setup do
      ChatRateLimiter.clear()
      :ok
    end

    test "live page renders two-column watch layout with chat drawer", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "layout-test",
          access_type: "public",
          mux_live_playback_id: "live_pb_layout"
        )

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ ~s(class="sv-live-watch-layout")
      assert html =~ ~s(class="sv-live-watch-player")
      assert html =~ ~s(data-test="chat-section")
      assert html =~ ~s(data-test="chat-toggle")
      assert html =~ ~s(data-test="sv-live-badge")
      assert html =~ ~s(data-chat-open="true")
    end

    test "toggle_chat flips the chat_open state", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          slug: "toggle-chat-test",
          access_type: "public",
          mux_live_playback_id: "live_pb_toggle"
        )

      conn = conn |> Map.put(:host, "#{org.slug}.localhost")
      {:ok, view, html} = live(conn, ~p"/events/#{event.slug}")

      assert html =~ ~s(data-chat-open="true")
      assert html =~ ~s(aria-expanded="true")

      html = render_click(view, "toggle_chat")
      assert html =~ ~s(data-chat-open="false")
      assert html =~ ~s(aria-expanded="false")

      html = render_click(view, "toggle_chat")
      assert html =~ ~s(data-chat-open="true")
    end
  end
end
