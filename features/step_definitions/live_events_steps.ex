defmodule MarqueeFeatures.Steps.LiveEvents do
  @moduledoc """
  Step definitions for the viewer-facing live event features:

    * live_events__live_event_calendar_export.feature — `GET
      /events/:slug/calendar.ics` is a plain controller download, so those
      steps issue the request the way a calendar client would
      (`Phoenix.ConnTest`) and assert on status, headers and the RFC 5545
      body.
    * live_events__live_event_google_calendar_link.feature — the add-to-
      Google-Calendar link is built by
      `LiveEventController.google_calendar_url/2` from an event and a base
      URL; the steps build the URL and decode its query string.
    * live_events__live_event_listing_viewer.feature — `GET /events` is a
      server-rendered page, driven through the Wallaby browser session.

  The organization is resolved from the `?org=<slug>` query parameter, the
  same fallback the tenant plug uses when no subdomain is present.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Phoenix.ConnTest, only: [build_conn: 0, get: 2]
  import Marquee.Factory
  import ExUnit.Assertions

  alias Marquee.Accounts.Scope
  alias Marquee.Streaming
  alias MarqueeWeb.Viewer.LiveEventController
  alias MarqueeWeb.WallabyCase

  @endpoint MarqueeWeb.Endpoint

  @google_render_endpoint "https://www.google.com/calendar/render?"
  @base_url "https://watch.example.test"

  # ---- Event setup ---------------------------------------------------------

  given_ "an organization has a scheduled event with a known slug and start time", fn world ->
    org = insert(:organization)
    start = future_at(3, ~T[18:00:00])

    event =
      insert(:live_event,
        organization: org,
        status: "scheduled",
        title: "Launch Party",
        slug: "launch-party",
        scheduled_start_at: start
      )

    Map.merge(world, %{org: org, event: event})
  end

  given_ "an organization has a scheduled event", fn world ->
    org = insert(:organization)

    event =
      insert(:live_event,
        organization: org,
        status: "scheduled",
        title: "Weekly Roundtable",
        description: "Line one, with a comma; and a semicolon",
        scheduled_start_at: future_at(2, ~T[15:00:00])
      )

    Map.merge(world, %{org: org, event: event})
  end

  given_ "an organization has a live event", fn world ->
    org = insert(:organization)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    event =
      insert(:live_event,
        organization: org,
        status: "live",
        title: "Happening Now",
        scheduled_start_at: DateTime.add(now, -600, :second),
        went_live_at: DateTime.add(now, -300, :second)
      )

    Map.merge(world, %{org: org, event: event})
  end

  given_ "an organization has an ended event", fn world ->
    org = insert(:organization)
    event = insert(:live_event, organization: org, status: "ended", title: "Last Week's Show") |> mark_ended()
    Map.merge(world, %{org: org, event: event})
  end

  given_ "an organization has a canceled event", fn world ->
    org = insert(:organization)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    event =
      insert(:live_event,
        organization: org,
        status: "canceled",
        title: "Called Off",
        canceled_at: now
      )

    Map.merge(world, %{org: org, event: event})
  end

  given_ "an organization has no event with slug {string}", fn world, slug ->
    org = insert(:organization)

    assert {:error, :not_found} = Streaming.get_live_event_by_slug(org, slug),
           "expected no live event with slug #{slug}"

    Map.merge(world, %{org: org, missing_slug: slug})
  end

  given_ "a scheduled event with an estimated duration of 90 minutes starting at 10:00 UTC",
         fn world ->
    org = insert(:organization)

    event =
      insert(:live_event,
        organization: org,
        status: "scheduled",
        title: "Morning Workshop",
        estimated_duration_minutes: 90,
        scheduled_start_at: future_at(4, ~T[10:00:00])
      )

    Map.merge(world, %{org: org, event: event})
  end

  given_ "a scheduled event with no estimated duration", fn world ->
    org = insert(:organization)

    event =
      insert(:live_event,
        organization: org,
        status: "scheduled",
        title: "Open-ended Hangout",
        estimated_duration_minutes: nil,
        scheduled_start_at: future_at(5, ~T[20:15:00])
      )

    Map.merge(world, %{org: org, event: event})
  end

  given_ "a scheduled event with a title, slug, start time, and description", fn world ->
    org = insert(:organization)

    event =
      insert(:live_event,
        organization: org,
        status: "scheduled",
        title: "Q&A Night: Ask Us Anything",
        slug: "qa-night",
        description: "Bring your questions & we'll answer live.",
        estimated_duration_minutes: 45,
        scheduled_start_at: future_at(6, ~T[19:30:00])
      )

    Map.merge(world, %{org: org, event: event})
  end

  given_ "an organization has a live event, a scheduled event, and an ended event", fn world ->
    org = insert(:organization)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    live =
      insert(:live_event,
        organization: org,
        status: "live",
        title: "Live Right Now",
        scheduled_start_at: DateTime.add(now, -600, :second),
        went_live_at: DateTime.add(now, -300, :second)
      )

    scheduled =
      insert(:live_event,
        organization: org,
        status: "scheduled",
        title: "Coming Up Soon",
        scheduled_start_at: future_at(2, ~T[18:00:00])
      )

    ended =
      insert(:live_event, organization: org, status: "ended", title: "Already Aired")
      |> mark_ended()

    Map.merge(world, %{
      org: org,
      live_event: live,
      scheduled_event: scheduled,
      ended_event: ended
    })
  end

  given_ "an organization has a live event with a Mux playback ID", fn world ->
    org = insert(:organization)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    event =
      insert(:live_event,
        organization: org,
        status: "live",
        title: "Streaming Live",
        mux_live_playback_id: "live_preview_playback_#{System.unique_integer([:positive])}",
        scheduled_start_at: DateTime.add(now, -600, :second),
        went_live_at: DateTime.add(now, -300, :second)
      )

    Map.merge(world, %{org: org, event: event})
  end

  given_ "an organization has a live event with a cover image but no playback ID", fn world ->
    org = insert(:organization)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    event =
      insert(:live_event,
        organization: org,
        status: "live",
        title: "Cover Only Stream",
        cover_image_url: "/images/logo.svg",
        mux_live_playback_id: nil,
        scheduled_start_at: DateTime.add(now, -600, :second),
        went_live_at: DateTime.add(now, -300, :second)
      )

    Map.merge(world, %{org: org, event: event})
  end

  given_ "an organization has a draft event", fn world ->
    org = insert(:organization)

    event =
      insert(:live_event,
        organization: org,
        status: "draft",
        title: "Secret Draft Stream",
        scheduled_start_at: future_at(3, ~T[12:00:00])
      )

    Map.merge(world, %{org: org, event: event})
  end

  given_ "an organization has no events", fn world ->
    org = insert(:organization)
    %{results: events} = Streaming.list_live_events(org, per_page: 100)
    assert events == [], "expected a fresh organization to have no live events"
    Map.put(world, :org, org)
  end

  given_ "an operator is logged in to their organization", fn world ->
    org = insert(:organization)
    user = insert(:user, confirmed_at: DateTime.utc_now())
    membership = insert(:membership, user: user, organization: org, role: :owner)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    session = WallabyCase.log_in_session(world.session, user, org)

    Map.merge(world, %{
      session: session,
      org: org,
      operator: user,
      membership: membership,
      scope: scope
    })
  end

  # ---- ICS download ---------------------------------------------------------

  when_ "a viewer requests the calendar.ics file for that event", fn world ->
    Map.put(world, :ics_conn, request_ics(world.org, world.event.slug))
  end

  when_ "a viewer downloads the ICS file", fn world ->
    conn = request_ics(world.org, world.event.slug)
    assert conn.status == 200, "expected the ICS download to succeed, got #{conn.status}"
    Map.put(world, :ics_conn, conn)
  end

  when_ "a viewer requests the calendar.ics file for that slug", fn world ->
    Map.put(world, :ics_conn, request_ics(world.org, world.missing_slug))
  end

  then_ "they receive a file with content-type text/calendar", fn world ->
    assert world.ics_conn.status == 200
    assert_calendar_content_type(world.ics_conn)
    world
  end

  then_ "the file has a content-disposition attachment header", fn world ->
    [disposition] = Plug.Conn.get_resp_header(world.ics_conn, "content-disposition")
    assert disposition == ~s(attachment; filename="#{world.event.slug}.ics")
    world
  end

  then_ "the file contains a valid VCALENDAR with the event summary", fn world ->
    assert_valid_vcalendar(world.ics_conn.resp_body, world.event)
    world
  end

  then_ "they receive a valid ICS file", fn world ->
    assert world.ics_conn.status == 200
    assert_calendar_content_type(world.ics_conn)
    assert_valid_vcalendar(world.ics_conn.resp_body, world.event)
    world
  end

  then_ "every line in the file ends with CRLF", fn world ->
    body = world.ics_conn.resp_body

    assert String.ends_with?(body, "\r\n"), "expected the ICS body to end with CRLF"

    lines = String.split(body, "\r\n", trim: true)
    assert length(lines) > 1, "expected a multi-line ICS body"

    bare_lf_lines = Enum.filter(lines, &String.contains?(&1, "\n"))
    assert bare_lf_lines == [], "expected no bare LF line endings, found: #{inspect(bare_lf_lines)}"
    world
  end

  then_ "the DTEND is 11:30 UTC on the same day", fn world ->
    dtstart = ics_datetime(world.ics_conn.resp_body, "DTSTART")
    dtend = ics_datetime(world.ics_conn.resp_body, "DTEND")

    assert DateTime.to_time(dtstart) == ~T[10:00:00]
    assert DateTime.to_date(dtend) == DateTime.to_date(dtstart)
    assert DateTime.to_time(dtend) == ~T[11:30:00]
    world
  end

  then_ "the DTEND is 1 hour after the start time", fn world ->
    dtstart = ics_datetime(world.ics_conn.resp_body, "DTSTART")
    dtend = ics_datetime(world.ics_conn.resp_body, "DTEND")

    assert dtstart == world.event.scheduled_start_at
    assert DateTime.diff(dtend, dtstart, :second) == 3600
    world
  end

  then_ "they receive a 404 response", fn world ->
    assert world.ics_conn.status == 404
    assert Plug.Conn.get_resp_header(world.ics_conn, "content-disposition") == []
    world
  end

  # ---- Google Calendar link ---------------------------------------------------

  when_ "the Google Calendar URL is generated for that event and base URL", fn world ->
    url = LiveEventController.google_calendar_url(world.event, @base_url)
    Map.merge(world, %{google_url: url, base_url: @base_url})
  end

  when_ "the Google Calendar URL is generated", fn world ->
    url = LiveEventController.google_calendar_url(world.event, @base_url)
    Map.merge(world, %{google_url: url, base_url: @base_url})
  end

  then_ "the URL starts with the Google Calendar render endpoint", fn world ->
    assert String.starts_with?(world.google_url, @google_render_endpoint)
    assert google_query(world.google_url)["action"] == "TEMPLATE"
    world
  end

  then_ "the URL includes the event title, start time, and event page URL as location", fn world ->
    query = google_query(world.google_url)
    [start_str, _end_str] = String.split(query["dates"], "/")

    assert query["text"] == world.event.title
    assert parse_utc_basic(start_str) == world.event.scheduled_start_at
    assert query["location"] == "#{world.base_url}/events/#{world.event.slug}"
    assert query["details"] == world.event.description
    world
  end

  then_ "the end time in the URL is 1 hour after the start time", fn world ->
    [start_str, end_str] = world.google_url |> google_query() |> Map.fetch!("dates") |> String.split("/")
    start_at = parse_utc_basic(start_str)

    assert start_at == world.event.scheduled_start_at
    assert DateTime.diff(parse_utc_basic(end_str), start_at, :second) == 3600
    world
  end

  # ---- Events listing (browser) -----------------------------------------------

  when_ "a viewer visits the events page for that organization", fn world ->
    Map.put(world, :session, visit_events_page(world))
  end

  when_ "a viewer visits the events page", fn world ->
    Map.put(world, :session, visit_events_page(world))
  end

  when_ "an unauthenticated visitor views the events page", fn world ->
    Map.put(world, :session, visit_events_page(world))
  end

  when_ "they visit the events page", fn world ->
    Map.put(world, :session, visit_events_page(world))
  end

  then_ "they see the live event in the live-now section", fn world ->
    assert_event_in_section(world.session, "live-now-section", world.live_event)
    world
  end

  then_ "they see the scheduled event in the upcoming section", fn world ->
    assert_event_in_section(world.session, "upcoming-section", world.scheduled_event)
    world
  end

  then_ "they see the ended event in the past section", fn world ->
    assert_event_in_section(world.session, "past-section", world.ended_event)
    world
  end

  then_ "the live event card embeds a muted autoplay video preview", fn world ->
    playback_id = world.event.mux_live_playback_id

    assert_has(
      world.session,
      css(
        "[data-test=live-now-section] [data-test=event-card] " <>
          "[data-test=event-live-preview][playback-id='#{playback_id}'][autoplay=muted][muted]",
        visible: :any
      )
    )

    world
  end

  then_ "the live event card displays the cover image instead of a video preview", fn world ->
    card = "[data-test=live-now-section] [data-test=event-card]"

    world.session
    |> assert_has(css(card, text: world.event.title))
    |> assert_has(css("#{card} img[src='#{world.event.cover_image_url}']", visible: :any))
    |> refute_has(css("#{card} [data-test=event-live-preview]", visible: :any))

    world
  end

  then_ "the draft event is not visible", fn world ->
    world.session
    |> assert_has(css("[data-test=events-index]"))
    |> refute_has(css("[data-test=event-card]", text: world.event.title))
    |> refute_has(css("[data-test=events-index]", text: world.event.title))

    world
  end

  then_ "they see the empty state indicator", fn world ->
    world.session
    |> assert_has(css("[data-test=no-events]"))
    |> refute_has(css("[data-test=event-card]"))

    world
  end

  then_ "the page renders successfully without requiring login", fn world ->
    assert current_path(world.session) == "/events"

    world.session
    |> assert_has(css("[data-test=events-index]"))
    |> assert_has(css("[data-test=upcoming-section] [data-test=event-card]", text: world.event.title))

    world
  end

  then_ "the page renders successfully", fn world ->
    assert current_path(world.session) == "/events"
    assert_has(world.session, css("[data-test=events-index]"))
    world
  end

  # ---- Helpers ------------------------------------------------------------------

  # A whole UTC datetime `days_ahead` days from today at `time`.
  defp future_at(days_ahead, %Time{} = time) do
    Date.utc_today()
    |> Date.add(days_ahead)
    |> DateTime.new!(time, "Etc/UTC")
  end

  defp mark_ended(event) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    event
    |> Ecto.Changeset.change(
      scheduled_start_at: DateTime.add(now, -3 * 86_400, :second),
      went_live_at: DateTime.add(now, -3 * 86_400, :second),
      ended_at: DateTime.add(now, -3 * 86_400 + 3600, :second)
    )
    |> Marquee.Repo.update!()
  end

  defp request_ics(org, slug) do
    get(build_conn(), "/events/#{slug}/calendar.ics?org=#{org.slug}")
  end

  defp assert_calendar_content_type(conn) do
    [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
    assert String.starts_with?(content_type, "text/calendar")
  end

  defp assert_valid_vcalendar(body, event) do
    lines = String.split(body, "\r\n", trim: true)

    assert List.first(lines) == "BEGIN:VCALENDAR"
    assert List.last(lines) == "END:VCALENDAR"
    assert "VERSION:2.0" in lines
    assert "BEGIN:VEVENT" in lines
    assert "END:VEVENT" in lines
    assert Enum.any?(lines, &String.starts_with?(&1, "DTSTART:"))
    assert Enum.any?(lines, &String.starts_with?(&1, "DTEND:"))
    assert "SUMMARY:#{ics_escape(event.title)}" in lines
  end

  defp ics_escape(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\n", "\\n")
  end

  defp ics_datetime(body, property) do
    body
    |> String.split("\r\n", trim: true)
    |> Enum.find_value(fn line ->
      case String.split(line, ":", parts: 2) do
        [^property, value] -> value
        _ -> nil
      end
    end)
    |> case do
      nil -> flunk("expected a #{property} line in the ICS body")
      value -> parse_utc_basic(value)
    end
  end

  # Parses an RFC 5545 / Google "basic" UTC timestamp: YYYYMMDDTHHMMSSZ.
  defp parse_utc_basic(
         <<y::binary-size(4), mo::binary-size(2), d::binary-size(2), "T", h::binary-size(2),
           mi::binary-size(2), s::binary-size(2), "Z">>
       ) do
    {:ok, dt, 0} = DateTime.from_iso8601("#{y}-#{mo}-#{d}T#{h}:#{mi}:#{s}Z")
    dt
  end

  defp parse_utc_basic(other), do: flunk("unexpected UTC timestamp format: #{inspect(other)}")

  defp google_query(url) do
    url
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end

  defp visit_events_page(world) do
    world.session
    |> visit("/events?org=#{world.org.slug}")
    |> assert_has(css("[data-test=events-index]"))
  end

  defp assert_event_in_section(session, section, event) do
    assert_has(session, css("[data-test=#{section}] [data-test=event-card]", text: event.title))
  end
end
