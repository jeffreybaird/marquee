defmodule BobineWeb.Viewer.LiveEventControllerTest do
  use BobineWeb.ConnCase, async: true

  alias BobineWeb.Viewer.LiveEventController

  # ---------------------------------------------------------------------------
  # GET /events — index
  # ---------------------------------------------------------------------------

  describe "GET /events" do
    test "renders event listing grouped by status", %{conn: conn} do
      org = insert(:organization)
      _live = insert(:live_event, organization: org, status: "live", title: "Now Streaming")

      _upcoming =
        insert(:live_event, organization: org, status: "scheduled", title: "Future Event")

      _past = insert(:live_event, organization: org, status: "ended", title: "Old Event")

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/events")

      assert html_response(conn, 200) =~ "Now Streaming"
      assert html_response(conn, 200) =~ "Future Event"
      assert html_response(conn, 200) =~ "Old Event"
    end

    test "shows live-now section when live events exist", %{conn: conn} do
      org = insert(:organization)
      insert(:live_event, organization: org, status: "live", title: "Live Right Now")

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/events")

      html = html_response(conn, 200)
      assert html =~ "data-test=\"live-now-section\""
      assert html =~ "Live Right Now"
    end

    test "shows upcoming section when scheduled events exist", %{conn: conn} do
      org = insert(:organization)
      insert(:live_event, organization: org, status: "scheduled", title: "Coming Up")

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/events")

      html = html_response(conn, 200)
      assert html =~ "data-test=\"upcoming-section\""
      assert html =~ "Coming Up"
    end

    test "shows empty state when no events", %{conn: conn} do
      org = insert(:organization)

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/events")

      html = html_response(conn, 200)
      assert html =~ "data-test=\"no-events\""
    end

    test "does not show draft events", %{conn: conn} do
      org = insert(:organization)
      insert(:live_event, organization: org, status: "draft", title: "Secret Draft")

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/events")

      refute html_response(conn, 200) =~ "Secret Draft"
    end

    test "works for unauthenticated viewer", %{conn: conn} do
      org = insert(:organization)

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/events")

      assert html_response(conn, 200)
    end

    test "works for authenticated operator visiting their org events page", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org)

      conn =
        conn_for(membership)
        |> get(~p"/events")

      assert html_response(conn, 200)
    end
  end

  # ---------------------------------------------------------------------------
  # GET /events/:slug/calendar.ics — calendar download
  # ---------------------------------------------------------------------------

  describe "GET /events/:slug/calendar.ics" do
    test "returns ICS file for a scheduled event", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          title: "My Live Event",
          slug: "my-live-event",
          scheduled_start_at: DateTime.new!(~D[2026-07-01], ~T[18:00:00], "Etc/UTC")
        )

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/events/#{event.slug}/calendar.ics")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") |> List.first() =~ "text/calendar"
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "attachment"
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "my-live-event.ics"

      body = response(conn, 200)
      assert body =~ "BEGIN:VCALENDAR"
      assert body =~ "BEGIN:VEVENT"
      assert body =~ "SUMMARY:My Live Event"
      assert body =~ "END:VCALENDAR"
    end

    test "returns ICS file for a live event", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          title: "Happening Now",
          slug: "happening-now",
          scheduled_start_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/events/#{event.slug}/calendar.ics")

      assert response(conn, 200)
      assert response(conn, 200) =~ "SUMMARY:Happening Now"
    end

    test "returns 404 for ended events", %{conn: conn} do
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "ended", slug: "old-event")

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/events/#{event.slug}/calendar.ics")

      assert response(conn, 404)
    end

    test "returns 404 for canceled events", %{conn: conn} do
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "canceled", slug: "canceled-event")

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/events/#{event.slug}/calendar.ics")

      assert response(conn, 404)
    end

    test "returns 404 for non-existent slug", %{conn: conn} do
      org = insert(:organization)

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/events/no-such-event/calendar.ics")

      assert response(conn, 404)
    end

    test "ICS uses CRLF line endings", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          slug: "crlf-test",
          scheduled_start_at: DateTime.new!(~D[2026-09-01], ~T[12:00:00], "Etc/UTC")
        )

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/events/#{event.slug}/calendar.ics")

      body = response(conn, 200)
      assert body =~ "\r\n"
    end

    test "ICS uses estimated_duration_minutes for DTEND", %{conn: conn} do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          slug: "duration-test",
          estimated_duration_minutes: 90,
          scheduled_start_at: DateTime.new!(~D[2026-09-01], ~T[10:00:00], "Etc/UTC")
        )

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> get(~p"/events/#{event.slug}/calendar.ics")

      body = response(conn, 200)
      # 10:00 + 90min = 11:30
      assert body =~ "DTEND:20260901T113000Z"
    end
  end

  # ---------------------------------------------------------------------------
  # google_calendar_url/2 — pure function, doctested but also unit-tested here
  # ---------------------------------------------------------------------------

  describe "google_calendar_url/2" do
    test "builds a valid Google Calendar URL" do
      event = %Bobine.Streaming.LiveEvent{
        title: "Test Event",
        slug: "test-event",
        scheduled_start_at: ~U[2026-08-01 19:00:00Z],
        estimated_duration_minutes: 60,
        description: "A great event"
      }

      url = LiveEventController.google_calendar_url(event, "https://acme.example.com")

      assert String.starts_with?(url, "https://www.google.com/calendar/render?")
      assert url =~ "action=TEMPLATE"
      assert url =~ URI.encode_www_form("Test Event")
      assert url =~ "20260801T190000Z"
      assert url =~ URI.encode_www_form("https://acme.example.com/events/test-event")
    end

    test "uses 1 hour default when no estimated_duration_minutes" do
      event = %Bobine.Streaming.LiveEvent{
        title: "No Duration",
        slug: "no-duration",
        scheduled_start_at: ~U[2026-08-01 10:00:00Z],
        estimated_duration_minutes: nil,
        description: nil
      }

      url = LiveEventController.google_calendar_url(event, "https://example.com")
      # end = 10:00 + 1hr = 11:00
      assert url =~ "20260801T110000Z"
    end
  end
end
