defmodule BobineWeb.Viewer.HistoryLive do
  use BobineWeb, :live_view

  alias Bobine.Engagement
  alias BobineWeb.Components.ViewerComponents
  alias BobineWeb.Components.ViewerLayout

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    %{results: history, total_pages: total_pages, page: page} =
      Engagement.list_watch_history(org, viewer, per_page: 24)

    {:ok,
     socket
     |> assign(:page_title, "Watch History")
     |> assign(:history, history)
     |> assign(:page, page)
     |> assign(:total_pages, total_pages)}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    next_page = socket.assigns.page + 1

    %{results: more} =
      Engagement.list_watch_history(org, viewer, page: next_page, per_page: 24)

    {:noreply,
     assign(socket,
       history: socket.assigns.history ++ more,
       page: next_page
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/history"
      theme={@theme}
      flash={@flash}
    >
      <div class="sv-page-content">
        <div class="sv-page-header">
          <h1 class="sv-page-title">Watch History</h1>
        </div>

        <ViewerComponents.empty_state
          :if={@history == []}
          title="No watch history yet"
          description="Videos you watch will appear here."
          icon="hero-clock"
        />

        <div :if={@history != []} class="sv-browse-grid" data-test="sv-history-grid">
          <div :for={entry <- @history} class="sv-history-card-wrapper">
            <ViewerComponents.content_card :if={entry.video} video={entry.video} size="grid" />
            <div class="sv-history-meta" style="margin-top: 4px; font-size: 0.75rem; color: var(--sv-text-secondary);">
              {format_relative_time(entry.watched_at)}
            </div>
          </div>
        </div>

        <div :if={@page < @total_pages} style="text-align: center; margin-top: 32px;">
          <button
            phx-click="load_more"
            class="sv-btn sv-btn-secondary"
            data-test="load-more-btn"
          >
            Load more
          </button>
        </div>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end

  defp format_relative_time(nil), do: ""

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86_400 -> "#{div(diff, 3600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86_400)} days ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end
end
