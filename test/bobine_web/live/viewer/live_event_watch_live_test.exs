defmodule BobineWeb.Viewer.LiveEventWatchLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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
        {:bobine_event, {:live_event_status_changed, updated}, %{organization: org}}
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
        {:bobine_event, {:live_event_status_changed, updated}, %{organization: org}}
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
        {:bobine_event, {:live_event_status_changed, updated_other}, %{organization: org}}
      )

      html = render(view)
      # My event should still show scheduled
      assert html =~ ~s(data-test="event-scheduled")
      refute html =~ ~s(data-test="event-live")
    end
  end
end
