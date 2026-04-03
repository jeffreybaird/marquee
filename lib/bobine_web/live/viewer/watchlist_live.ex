defmodule BobineWeb.Viewer.WatchlistLive do
  use BobineWeb, :live_view

  alias Bobine.Engagement
  alias BobineWeb.Components.ViewerLayout
  alias BobineWeb.Components.ViewerComponents

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    %{results: items} = Engagement.list_viewer_watchlist(org, viewer.id, per_page: 100)

    videos = Enum.map(items, & &1.video) |> Enum.reject(&is_nil/1)

    {:ok,
     socket
     |> assign(:page_title, "Watchlist")
     |> assign(:videos, videos)
     |> assign(:watchlist_items, items)}
  end

  @impl true
  def handle_event("remove", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    case Engagement.remove_from_viewer_watchlist(org.id, viewer.id, video_id) do
      {:ok, _} ->
        videos = Enum.reject(socket.assigns.videos, &(&1.id == video_id))
        {:noreply, assign(socket, :videos, videos)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/watchlist"
      theme={@theme}
      flash={@flash}
    >
      <div class="sv-page-content">
        <div class="sv-page-header">
          <h1 class="sv-page-title">My Watchlist</h1>
        </div>

        <ViewerComponents.empty_state
          :if={@videos == []}
          title="Your watchlist is empty"
          description="Browse content to add videos."
          icon="hero-bookmark"
        >
          <.link navigate="/browse" class="sv-btn sv-btn-accent" style="margin-top: 16px">
            Browse content
          </.link>
        </ViewerComponents.empty_state>

        <div :if={@videos != []} class="sv-browse-grid" data-test="sv-watchlist-grid">
          <div :for={video <- @videos} class="sv-watchlist-card-wrapper">
            <ViewerComponents.content_card video={video} size="grid" />
            <button
              phx-click="remove"
              phx-value-video-id={video.id}
              class="sv-btn sv-btn-ghost"
              style="width: 100%; margin-top: 8px; font-size: 0.8125rem"
              data-test={"sv-watchlist-remove-#{video.id}"}
            >
              <.icon name="hero-x-mark" class="size-4 mr-1" aria-hidden="true" /> Remove
            </button>
          </div>
        </div>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end
end
