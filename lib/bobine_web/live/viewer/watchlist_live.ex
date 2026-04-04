defmodule BobineWeb.Viewer.WatchlistLive do
  @moduledoc """
  Tabbed library page serving three routes: /watchlist, /favorites, /queue.
  Active tab is derived from the URL path. Queue tab supports drag-and-drop
  reordering via QueueSortable hook.

  Hooks: QueueSortable (queue tab), CardFocus (via content_card)
  Events: reorder_queue, remove_from_queue, card actions (via CardActions)
  Routes: /watchlist, /favorites, /queue (viewer_subscribed session)
  """

  use BobineWeb, :live_view
  use BobineWeb.Viewer.CardActions

  alias Bobine.Engagement
  alias BobineWeb.Components.ViewerComponents
  alias BobineWeb.Components.ViewerLayout

  @tab_for_path %{
    "/watchlist" => "watchlist",
    "/favorites" => "favorites",
    "/queue" => "queue"
  }

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    videos = Engagement.list_viewer_watchlist_videos(org, viewer.id, per_page: 100)
    %{results: favorites} = Engagement.list_favorites(org, viewer)
    queue_items = Engagement.list_queue(org, viewer)

    {:ok,
     socket
     |> assign(:page_title, "My Library")
     |> assign(:videos, videos)
     |> assign(:favorites, favorites)
     |> assign(:queue_items, queue_items)
     |> assign(:active_tab, "watchlist")}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    path = URI.parse(uri).path
    tab = Map.get(@tab_for_path, path, "watchlist")
    {:noreply, assign(socket, :active_tab, tab)}
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

  def handle_event("unfavorite", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    video = %{id: video_id}

    case Engagement.toggle_favorite(org, viewer, video) do
      {:ok, :removed} ->
        favorites = Enum.reject(socket.assigns.favorites, &(&1.video_id == video_id))
        {:noreply, assign(socket, :favorites, favorites)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_from_queue", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    video = %{id: video_id}

    Engagement.remove_from_queue(org, viewer, video)
    queue_items = Enum.reject(socket.assigns.queue_items, &(&1.video_id == video_id))
    {:noreply, assign(socket, :queue_items, queue_items)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    path = tab_path(tab)
    {:noreply, push_patch(socket, to: path)}
  end

  defp tab_path("favorites"), do: "/favorites"
  defp tab_path("queue"), do: "/queue"
  defp tab_path(_), do: "/watchlist"

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path={tab_path(@active_tab)}
      theme={@theme}
      flash={@flash}
    >
      <div class="sv-page-content">
        <div class="sv-page-header">
          <h1 class="sv-page-title">My Library</h1>
        </div>

        <div class="sv-tabs" role="tablist">
          <button
            phx-click="switch_tab"
            phx-value-tab="watchlist"
            class={["sv-tab", @active_tab == "watchlist" && "active"]}
            role="tab"
            aria-selected={to_string(@active_tab == "watchlist")}
            data-test="watchlist-tab"
          >
            Watchlist
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="favorites"
            class={["sv-tab", @active_tab == "favorites" && "active"]}
            role="tab"
            aria-selected={to_string(@active_tab == "favorites")}
            data-test="favorites-tab"
          >
            Favorites
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="queue"
            class={["sv-tab", @active_tab == "queue" && "active"]}
            role="tab"
            aria-selected={to_string(@active_tab == "queue")}
            data-test="queue-tab"
          >
            Queue
          </button>
        </div>

        <%!-- Watchlist tab --%>
        <div :if={@active_tab == "watchlist"} role="tabpanel" data-test="watchlist-panel">
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
              <ViewerComponents.content_card
                video={video}
                size="grid"
                current_viewer={@current_viewer}
                favorited_ids={@favorited_ids}
                watchlisted_ids={@watchlisted_ids}
                queued_ids={@queued_ids}
              />
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

        <%!-- Favorites tab --%>
        <div :if={@active_tab == "favorites"} role="tabpanel" data-test="favorites-panel">
          <ViewerComponents.empty_state
            :if={@favorites == []}
            title="No favorites yet"
            description="Tap the heart icon on videos to add them here."
            icon="hero-heart"
          />

          <div :if={@favorites != []} class="sv-browse-grid" data-test="sv-favorites-grid">
            <div :for={fav <- @favorites} class="sv-watchlist-card-wrapper">
              <ViewerComponents.content_card
                :if={fav.video}
                video={fav.video}
                size="grid"
                current_viewer={@current_viewer}
                favorited_ids={@favorited_ids}
                watchlisted_ids={@watchlisted_ids}
                queued_ids={@queued_ids}
              />
              <button
                phx-click="unfavorite"
                phx-value-video-id={fav.video_id}
                class="sv-btn sv-btn-ghost"
                style="width: 100%; margin-top: 8px; font-size: 0.8125rem"
                data-test={"sv-favorite-remove-#{fav.video_id}"}
              >
                <.icon name="hero-heart" class="size-4 mr-1" aria-hidden="true" /> Unfavorite
              </button>
            </div>
          </div>
        </div>

        <%!-- Queue tab --%>
        <div :if={@active_tab == "queue"} role="tabpanel" data-test="queue-panel">
          <ViewerComponents.empty_state
            :if={@queue_items == []}
            title="Your queue is empty"
            description="Add videos to your queue from any video card."
            icon="hero-queue-list"
          >
            <.link navigate="/browse" class="sv-btn sv-btn-accent" style="margin-top: 16px">
              Browse content
            </.link>
          </ViewerComponents.empty_state>

          <div :if={@queue_items != []} class="sv-browse-grid" data-test="sv-queue-grid">
            <div :for={item <- @queue_items} :if={item.video} class="sv-watchlist-card-wrapper">
              <ViewerComponents.content_card
                video={item.video}
                size="grid"
                current_viewer={@current_viewer}
                favorited_ids={@favorited_ids}
                watchlisted_ids={@watchlisted_ids}
                queued_ids={@queued_ids}
              />
              <button
                phx-click="remove_from_queue"
                phx-value-video-id={item.video_id}
                class="sv-btn sv-btn-ghost"
                style="width: 100%; margin-top: 8px; font-size: 0.8125rem"
                data-test={"sv-queue-remove-#{item.video_id}"}
              >
                <.icon name="hero-x-mark" class="size-4 mr-1" aria-hidden="true" /> Remove
              </button>
            </div>
          </div>
        </div>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end
end
