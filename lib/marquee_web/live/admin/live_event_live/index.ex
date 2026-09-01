defmodule MarqueeWeb.Admin.LiveEventLive.Index do
  @moduledoc """
  Lists all live events for the current organization with status filtering
  and real-time updates via PubSub.

  Route: GET /admin/live-events
  """

  use MarqueeWeb, :live_view

  alias Marquee.Events
  alias Marquee.Streaming

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization

    if connected?(socket) do
      Events.subscribe(org.id)
    end

    {:ok,
     socket
     |> assign(:page_title, "Live Events")
     |> assign(:status_filter, "")
     |> assign(:page, 1)
     |> load_events()}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> assign(:page, 1)
     |> load_events()}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(:page, String.to_integer(page))
     |> load_events()}
  end

  @impl true
  def handle_info({:marquee_event, {:live_event_created, _event}, _scope}, socket) do
    {:noreply, load_events(socket)}
  end

  @impl true
  def handle_info({:marquee_event, {:live_event_updated, _event}, _scope}, socket) do
    {:noreply, load_events(socket)}
  end

  @impl true
  def handle_info({:marquee_event, {:live_event_deleted, _event}, _scope}, socket) do
    {:noreply, load_events(socket)}
  end

  @impl true
  def handle_info({:marquee_event, {:live_event_status_changed, _event}, _scope}, socket) do
    {:noreply, load_events(socket)}
  end

  @impl true
  def handle_info({:marquee_event, _event, _scope}, socket) do
    {:noreply, socket}
  end

  defp load_events(socket) do
    org = socket.assigns.organization
    page = socket.assigns.page
    status_filter = socket.assigns.status_filter

    opts = [page: page, per_page: @per_page]
    opts = if status_filter != "", do: Keyword.put(opts, :status, status_filter), else: opts

    result = Streaming.list_live_events(org, opts)

    socket
    |> assign(:events_page, result)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      trial_status={@trial_status}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
      flash={@flash}
    >
      <div class="flex items-center justify-between">
        <.header>Live Events</.header>
        <.link
          navigate={~p"/admin/live-events/new"}
          class="inline-flex items-center gap-2 rounded-md bg-admin-accent px-4 py-2 font-ui text-sm font-medium text-white hover:opacity-90"
          data-test="new-live-event-btn"
        >
          New Live Event
        </.link>
      </div>

      <%!-- Status filter --%>
      <form phx-change="filter_status" class="mt-4" aria-label="Filter live events by status">
        <label for="status-filter" class="sr-only">Filter by status</label>
        <select
          id="status-filter"
          name="status"
          class="rounded-md border border-admin-border bg-admin-card px-3 py-1.5 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
          data-test="status-filter"
        >
          <option value="" selected={@status_filter == ""}>All statuses</option>
          <option value="draft" selected={@status_filter == "draft"}>Draft</option>
          <option value="scheduled" selected={@status_filter == "scheduled"}>Scheduled</option>
          <option value="live" selected={@status_filter == "live"}>Live</option>
          <option value="ended" selected={@status_filter == "ended"}>Ended</option>
          <option value="canceled" selected={@status_filter == "canceled"}>Canceled</option>
          <option value="did_not_occur" selected={@status_filter == "did_not_occur"}>
            Did Not Occur
          </option>
        </select>
      </form>

      <%!-- Event list --%>
      <div class="mt-6" data-test="live-events-list">
        <.table id="live-events-table" rows={@events_page.results}>
          <:col :let={event} label="Title">
            <.link
              navigate={~p"/admin/live-events/#{event.slug}"}
              class="font-medium text-admin-fg hover:text-admin-accent"
              data-test={"event-title-#{event.id}"}
            >
              {event.title}
            </.link>
          </:col>
          <:col :let={event} label="Slug">
            <span class="font-mono text-xs text-admin-muted">{event.slug}</span>
          </:col>
          <:col :let={event} label="Status">
            <span class={"rounded-full px-2 py-0.5 font-ui text-xs #{status_badge(event.status)}"}>
              {format_status(event.status)}
            </span>
          </:col>
          <:col :let={event} label="Access">
            <span class="font-ui text-xs text-admin-muted">
              {format_access_type(event.access_type)}
            </span>
          </:col>
          <:col :let={event} label="Scheduled">
            <span class="font-ui text-xs text-admin-muted">
              {format_datetime(event.scheduled_start_at)}
            </span>
          </:col>
          <:action :let={event}>
            <div class="flex gap-1" data-test={"event-row-#{event.id}"}>
              <.link
                navigate={~p"/admin/live-events/#{event.slug}"}
                class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
                data-test={"view-event-#{event.id}"}
              >
                View
              </.link>
              <.link
                navigate={~p"/admin/live-events/#{event.slug}/edit"}
                class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
                data-test={"edit-event-#{event.id}"}
              >
                Edit
              </.link>
            </div>
          </:action>
        </.table>

        <p
          :if={@events_page.results == []}
          class="mt-8 text-center text-admin-muted"
          data-test="empty-state"
        >
          No live events yet.
        </p>

        <nav
          :if={@events_page.total_pages > 1}
          class="mt-4 flex items-center justify-between"
          aria-label="Pagination"
          data-test="events-pagination"
        >
          <span class="text-sm text-admin-muted">
            Page {@events_page.page} of {@events_page.total_pages} ({@events_page.total} events)
          </span>
          <div class="flex gap-2">
            <button
              phx-click="page"
              phx-value-page={@events_page.page - 1}
              disabled={@events_page.page <= 1}
              class="rounded-md border border-admin-border px-3 py-1.5 font-ui text-sm text-admin-fg hover:bg-admin-card disabled:cursor-not-allowed disabled:opacity-50"
              data-test="events-prev-page"
            >
              Previous
            </button>
            <button
              phx-click="page"
              phx-value-page={@events_page.page + 1}
              disabled={@events_page.page >= @events_page.total_pages}
              class="rounded-md border border-admin-border px-3 py-1.5 font-ui text-sm text-admin-fg hover:bg-admin-card disabled:cursor-not-allowed disabled:opacity-50"
              data-test="events-next-page"
            >
              Next
            </button>
          </div>
        </nav>
      </div>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp status_badge("live"), do: "border border-error/40 bg-error/10 text-error"
  defp status_badge("scheduled"), do: "border border-info/40 bg-info/10 text-admin-fg"
  defp status_badge("ended"), do: "bg-admin-card text-admin-muted"
  defp status_badge("canceled"), do: "bg-admin-card text-admin-muted"
  defp status_badge("did_not_occur"), do: "border border-warning/40 bg-warning/10 text-warning"
  defp status_badge(_), do: "bg-admin-card text-admin-muted"

  defp format_status("did_not_occur"), do: "Did Not Occur"
  defp format_status(status), do: String.capitalize(status)

  defp format_access_type("subscribers_only"), do: "Subscribers Only"
  defp format_access_type("pay_per_view"), do: "Pay Per View"
  defp format_access_type("public"), do: "Public"
  defp format_access_type(type), do: type

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M UTC")
  end
end
