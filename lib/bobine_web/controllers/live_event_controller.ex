defmodule BobineWeb.Viewer.LiveEventController do
  @moduledoc """
  Controller for viewer-facing live event listing and calendar export.

  Uses a plain controller (not LiveView) because the events index is
  mostly static and doesn't need real-time updates — the detail page
  (LiveEventWatchLive) handles real-time status transitions.

  Routes:
    GET /events                  — event listing (live now / upcoming / past)
    GET /events/:slug/calendar.ics — iCalendar download for a scheduled event
  """

  use BobineWeb, :controller

  alias Bobine.Branding
  alias Bobine.Streaming
  alias Bobine.Viewers

  @doc """
  Lists live events grouped by status.

  Exempt from doctest — hits the database.
  """
  def index(conn, _params) do
    org = conn.assigns.organization
    viewer = resolve_viewer(conn)
    theme = Branding.get_theme_or_default_cached(org)

    %{results: live_now} = Streaming.list_live_events(org, status: "live", per_page: 20)
    %{results: upcoming} = Streaming.list_live_events(org, status: "scheduled", per_page: 50)
    %{results: past} = Streaming.list_live_events(org, status: "ended", per_page: 20)

    render(conn, :index,
      organization: org,
      current_viewer: viewer,
      impersonating_viewer: impersonating?(conn, viewer),
      theme: theme,
      live_now: live_now,
      upcoming: upcoming,
      past: past
    )
  end

  @doc """
  Serves an iCalendar (.ics) file for a scheduled or upcoming live event.

  Returns 404 if the event is not found or is not in scheduled status.

  Exempt from doctest — hits the database.
  """
  def calendar_ics(conn, %{"slug" => slug}) do
    org = conn.assigns.organization

    case Streaming.get_live_event_by_slug(org, slug) do
      {:ok, event} when event.status in ["scheduled", "live"] ->
        ics = build_ics(event, conn)

        conn
        |> put_resp_content_type("text/calendar")
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"#{event.slug}.ics\""
        )
        |> send_resp(200, ics)

      {:ok, _event} ->
        conn
        |> put_status(404)
        |> put_view(BobineWeb.ErrorHTML)
        |> render(:"404")

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(BobineWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  @doc """
  Builds a Google Calendar add-event URL for a live event.

  Accepts a `%LiveEvent{}` and a base URL string (e.g. "https://example.com")
  used to construct the event detail link.

  ## Examples

      iex> event = %Bobine.Streaming.LiveEvent{
      ...>   title: "My Stream",
      ...>   slug: "my-stream",
      ...>   scheduled_start_at: ~U[2026-06-01 18:00:00Z],
      ...>   estimated_duration_minutes: 60,
      ...>   description: nil
      ...> }
      iex> url = BobineWeb.Viewer.LiveEventController.google_calendar_url(event, "https://example.com")
      iex> String.starts_with?(url, "https://www.google.com/calendar/render?action=TEMPLATE")
      true

  """
  def google_calendar_url(event, base_url) do
    start_str = format_google_dt(event.scheduled_start_at)
    end_str = end_time_for_google(event)
    event_url = "#{base_url}/events/#{event.slug}"
    description = event.description || ""

    params = %{
      "action" => "TEMPLATE",
      "text" => event.title,
      "dates" => "#{start_str}/#{end_str}",
      "details" => description,
      "location" => event_url
    }

    "https://www.google.com/calendar/render?" <> URI.encode_query(params)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp resolve_viewer(conn) do
    case get_session(conn, :viewer_token) do
      nil -> nil
      token -> Viewers.get_viewer_by_session_token(token)
    end
  end

  defp impersonating?(conn, viewer) do
    viewer != nil && not is_nil(get_session(conn, :impersonating_viewer_id))
  end

  defp build_ics(event, conn) do
    uid = "live-event-#{event.id}@#{conn.host}"
    dtstart = format_ics_dt(event.scheduled_start_at)
    dtend = format_ics_dt(end_datetime(event))
    now = format_ics_dt(DateTime.utc_now())
    summary = ics_escape(event.title)
    description = ics_escape(event.description || "")
    url = "https://#{conn.host}/events/#{event.slug}"

    """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//Bobine//LiveEvent//EN
    CALSCALE:GREGORIAN
    METHOD:PUBLISH
    BEGIN:VEVENT
    UID:#{uid}
    DTSTAMP:#{now}
    DTSTART:#{dtstart}
    DTEND:#{dtend}
    SUMMARY:#{summary}
    DESCRIPTION:#{description}
    URL:#{url}
    END:VEVENT
    END:VCALENDAR
    """
    |> String.replace("\n", "\r\n")
  end

  defp end_datetime(%{estimated_duration_minutes: min, scheduled_start_at: start})
       when is_integer(min) and min > 0 do
    DateTime.add(start, min * 60, :second)
  end

  defp end_datetime(%{scheduled_start_at: start}) do
    DateTime.add(start, 3600, :second)
  end

  defp end_time_for_google(event) do
    format_google_dt(end_datetime(event))
  end

  defp format_ics_dt(%DateTime{} = dt) do
    dt = DateTime.truncate(dt, :second)

    "#{pad(dt.year, 4)}#{pad(dt.month, 2)}#{pad(dt.day, 2)}T#{pad(dt.hour, 2)}#{pad(dt.minute, 2)}#{pad(dt.second, 2)}Z"
  end

  defp format_google_dt(%DateTime{} = dt) do
    dt = DateTime.truncate(dt, :second)

    "#{pad(dt.year, 4)}#{pad(dt.month, 2)}#{pad(dt.day, 2)}T#{pad(dt.hour, 2)}#{pad(dt.minute, 2)}#{pad(dt.second, 2)}Z"
  end

  defp pad(n, width), do: String.pad_leading(Integer.to_string(n), width, "0")

  defp ics_escape(nil), do: ""

  defp ics_escape(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\n", "\\n")
  end
end
