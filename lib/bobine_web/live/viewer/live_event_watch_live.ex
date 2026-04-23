defmodule BobineWeb.Viewer.LiveEventWatchLive do
  @moduledoc """
  Viewer-facing live event detail and watch page.

  Renders differently based on event status:

    * `scheduled`  — countdown, description, reminder toggle, calendar links
    * `live`       — Mux HLS live player (access-controlled)
    * `ended`      — recording player via `recording_video` association (if available)
    * `canceled`   — cancellation notice
    * `did_not_occur` — did-not-occur notice
    * `draft`      — 404 redirect (not publicly visible)

  Subscribes to org-level events to handle real-time status transitions
  (e.g. `scheduled → live`) without a page reload.

  Route: /events/:slug (viewer_public session, optional auth)
  """

  use BobineWeb, :live_view

  alias Bobine.Events
  alias Bobine.Streaming
  alias BobineWeb.Components.ViewerComponents
  alias BobineWeb.Components.ViewerLayout
  alias BobineWeb.Viewer.LiveEventController

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns[:current_viewer]

    case Streaming.get_live_event_by_slug(org, slug) do
      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/events")}

      {:ok, %{status: "draft"}} ->
        {:ok, push_navigate(socket, to: ~p"/events")}

      {:ok, event} ->
        if connected?(socket) do
          Events.subscribe(org.id)
        end

        event = maybe_preload_recording(event)
        has_reminder = viewer != nil && Streaming.has_reminder?(event, viewer)
        access = Streaming.check_event_access(event, viewer)
        base_url = build_base_url(socket)

        {:ok,
         socket
         |> assign(:page_title, event.title)
         |> assign(:event, event)
         |> assign(:has_reminder, has_reminder)
         |> assign(:access, access)
         |> assign(:base_url, base_url)}
    end
  end

  @impl true
  def handle_event("toggle_reminder", _params, socket) do
    viewer = socket.assigns[:current_viewer]

    if viewer do
      {:noreply, apply_reminder_toggle(socket, viewer)}
    else
      {:noreply, push_navigate(socket, to: ~p"/login")}
    end
  end

  defp apply_reminder_toggle(socket, viewer) do
    event = socket.assigns.event

    if socket.assigns.has_reminder do
      Streaming.remove_reminder(event, viewer)
      assign(socket, :has_reminder, false)
    else
      assign(socket, :has_reminder, add_reminder_status(event, viewer))
    end
  end

  defp add_reminder_status(event, viewer) do
    case Streaming.add_reminder(event, viewer) do
      {:ok, _reminder} -> true
      {:error, :already_set} -> true
      _error -> false
    end
  end

  @impl true
  def handle_info({:bobine_event, {:live_event_status_changed, updated_event}, _scope}, socket) do
    if updated_event.id == socket.assigns.event.id do
      viewer = socket.assigns[:current_viewer]
      updated_event = maybe_preload_recording(updated_event)
      access = Streaming.check_event_access(updated_event, viewer)

      {:noreply,
       socket
       |> assign(:event, updated_event)
       |> assign(:access, access)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:bobine_event, _event, _scope}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/events"
      theme={@theme}
      flash={@flash}
    >
      <div class="sv-page-content" data-test="live-event-watch">
        {render_event_body(assigns)}
      </div>
    </ViewerLayout.viewer_layout>
    """
  end

  # ---------------------------------------------------------------------------
  # Status-specific render helpers
  # ---------------------------------------------------------------------------

  defp render_event_body(%{event: %{status: "scheduled"}} = assigns) do
    ~H"""
    <article aria-labelledby="event-title" data-test="event-scheduled">
      <.event_cover event={@event} />
      <div class="sv-event-detail">
        <h1 id="event-title" class="sv-page-title">{@event.title}</h1>
        <p class="sv-event-meta">
          <time datetime={DateTime.to_iso8601(@event.scheduled_start_at)}>
            {Calendar.strftime(@event.scheduled_start_at, "%B %-d, %Y at %-I:%M %p UTC")}
          </time>
        </p>
        <p :if={@event.description} class="sv-event-description">{@event.description}</p>

        <div class="sv-event-actions" data-test="event-actions">
          <button
            phx-click="toggle_reminder"
            class="sv-btn sv-btn-accent"
            aria-pressed={to_string(@has_reminder)}
            data-test="reminder-toggle"
          >
            {if @has_reminder, do: "Remove reminder", else: "Remind me"}
          </button>

          <a
            href={~p"/events/#{@event.slug}/calendar.ics"}
            class="sv-btn sv-btn-secondary"
            aria-label={"Download #{@event.title} calendar file"}
            data-test="ics-download"
          >
            Add to calendar (.ics)
          </a>

          <a
            href={LiveEventController.google_calendar_url(@event, @base_url)}
            target="_blank"
            rel="noopener noreferrer"
            class="sv-btn sv-btn-secondary"
            aria-label={"Add #{@event.title} to Google Calendar"}
            data-test="google-calendar-link"
          >
            Add to Google Calendar
          </a>
        </div>
      </div>
    </article>
    """
  end

  defp render_event_body(%{event: %{status: "live"}} = assigns) do
    ~H"""
    <article aria-labelledby="event-title" data-test="event-live">
      <h1 id="event-title" class="sv-page-title">{@event.title}</h1>
      <span class="sv-event-badge sv-event-badge--live" aria-label="Live now">LIVE</span>
      {render_live_player(assigns)}
      <p :if={@event.description} class="sv-event-description">{@event.description}</p>
    </article>
    """
  end

  defp render_event_body(%{event: %{status: "ended"}} = assigns) do
    ~H"""
    <article aria-labelledby="event-title" data-test="event-ended">
      <.event_cover event={@event} />
      <div class="sv-event-detail">
        <h1 id="event-title" class="sv-page-title">{@event.title}</h1>
        <p class="sv-event-meta">This event has ended.</p>
        <p :if={@event.description} class="sv-event-description">{@event.description}</p>
        <div :if={@event.recording_video_id} data-test="recording-player">
          <h2 class="sv-section-title">Watch the recording</h2>
          {render_recording_player(assigns)}
        </div>
        <p :if={!@event.recording_video_id} class="sv-event-meta" data-test="no-recording">
          A recording of this event is not available.
        </p>
      </div>
    </article>
    """
  end

  defp render_event_body(%{event: %{status: status}} = assigns)
       when status in ["canceled", "did_not_occur"] do
    ~H"""
    <article aria-labelledby="event-title" data-test="event-canceled">
      <.event_cover event={@event} />
      <div class="sv-event-detail">
        <h1 id="event-title" class="sv-page-title">{@event.title}</h1>
        <p class="sv-event-meta" data-test="canceled-message">
          {if @event.status == "canceled",
            do: "This event has been canceled.",
            else: "This event did not occur as scheduled."}
        </p>
      </div>
    </article>
    """
  end

  defp render_event_body(assigns) do
    ~H"""
    <div data-test="event-unknown-status">
      <p>This event is no longer available.</p>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Live player (access controlled)
  # ---------------------------------------------------------------------------

  defp render_live_player(%{access: {:ok, :allowed}} = assigns) do
    ~H"""
    <ViewerComponents.live_event_player event={@event} />
    """
  end

  defp render_live_player(%{access: {:error, :access_denied, :no_subscription}} = assigns) do
    ~H"""
    <div class="sv-access-denied" data-test="access-denied-subscription">
      <p>This event is for subscribers only.</p>
      <a href={~p"/subscribe"} class="sv-btn sv-btn-accent">Subscribe to watch</a>
    </div>
    """
  end

  defp render_live_player(%{access: {:error, :access_denied, :no_ticket}} = assigns) do
    ~H"""
    <div class="sv-access-denied" data-test="access-denied-ticket">
      <p>This is a pay-per-view event.</p>
      <a href={~p"/events/#{@event.slug}"} class="sv-btn sv-btn-accent">Get access</a>
    </div>
    """
  end

  defp render_live_player(%{access: {:error, :access_denied, :ticket_expired}} = assigns) do
    ~H"""
    <div class="sv-access-denied" data-test="access-denied-expired">
      <p>Your access to this event has expired.</p>
    </div>
    """
  end

  defp render_live_player(assigns) do
    ~H"""
    <div class="sv-access-denied" data-test="access-denied-generic">
      <p>You don't have access to watch this event.</p>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Recording player (for ended events)
  # ---------------------------------------------------------------------------

  defp render_recording_player(
         %{access: {:ok, :allowed}, event: %{recording_video: video}} = assigns
       )
       when not is_nil(video) and not is_struct(video, Ecto.Association.NotLoaded) do
    ~H"""
    <ViewerComponents.video_player video={@event.recording_video} />
    """
  end

  defp render_recording_player(%{access: {:error, :access_denied, _reason}} = assigns) do
    ~H"""
    <div class="sv-access-denied" data-test="access-denied-recording">
      <p>
        {case elem(@access, 2) do
          :no_subscription -> "Recording is available to subscribers only."
          :no_ticket -> "Recording is pay-per-view."
          :ticket_expired -> "Your access to this recording has expired."
          _ -> "You don't have access to this recording."
        end}
      </p>
    </div>
    """
  end

  defp render_recording_player(assigns) do
    ~H"""
    <div data-test="no-recording-access">
      <p>Recording is not available.</p>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Shared sub-components
  # ---------------------------------------------------------------------------

  defp event_cover(%{event: %{cover_image_url: nil}} = assigns) do
    ~H"""
    <div class="sv-event-cover-placeholder" aria-hidden="true" />
    """
  end

  defp event_cover(assigns) do
    ~H"""
    <div class="sv-event-cover" aria-hidden="true">
      <img src={@event.cover_image_url} alt="" class="sv-event-cover-img" />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp maybe_preload_recording(%{recording_video_id: nil} = event), do: event

  defp maybe_preload_recording(%{recording_video_id: _vid_id} = event) do
    Streaming.preload_recording_video(event)
  end

  defp build_base_url(socket) do
    host_uri = socket.host_uri

    if host_uri do
      scheme = host_uri.scheme || "https"
      port_suffix = port_suffix(scheme, host_uri.port)
      "#{scheme}://#{host_uri.host}#{port_suffix}"
    else
      ""
    end
  end

  defp port_suffix("http", 80), do: ""
  defp port_suffix("https", 443), do: ""
  defp port_suffix(_scheme, nil), do: ""
  defp port_suffix(_scheme, port), do: ":#{port}"
end
