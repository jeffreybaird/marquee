defmodule MarqueeWeb.Viewer.WatchlistLive do
  @moduledoc """
  Tabbed library page serving three routes: /watchlist, /favorites, /queue.
  Active tab is derived from the URL path. Queue tab supports drag-and-drop
  reordering via QueueSortable hook.

  Hooks: QueueSortable (queue tab), CardFocus (via content_card)
  Events: reorder_queue, remove_from_queue, card actions (via CardActions)
  Routes: /watchlist, /favorites, /queue (viewer_subscribed session)
  """

  use MarqueeWeb, :live_view
  use MarqueeWeb.Viewer.CardActions

  alias Marquee.Engagement
  alias MarqueeWeb.Components.ViewerComponents
  alias MarqueeWeb.Components.ViewerLayout

  import MarqueeWeb.Viewer.WatchLive.Components, only: [format_duration: 1]

  @tab_for_path %{
    "/watchlist" => "watchlist",
    "/favorites" => "favorites",
    "/queue" => "queue"
  }

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    %{results: watchlist_items} = Engagement.list_viewer_watchlist(org, viewer.id, per_page: 100)
    %{results: favorites} = Engagement.list_favorites(org, viewer)
    %{results: queue_items} = Engagement.list_queue(org, viewer, per_page: 100)

    {:ok,
     socket
     |> assign(:page_title, "My Library")
     |> assign(:watchlist_items, watchlist_items)
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
        items =
          Enum.reject(socket.assigns.watchlist_items, fn item ->
            item.item_type == :video and item.video_id == video_id
          end)

        {:noreply, assign(socket, :watchlist_items, items)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_watchlist_item", %{"item-id" => item_id}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    case find_watchlist_item(socket.assigns.watchlist_items, item_id) do
      nil ->
        {:noreply, socket}

      item ->
        target = watchlist_item_target(item)

        if target do
          Engagement.remove_from_watchlist(org, viewer, target)
        end

        items = Enum.reject(socket.assigns.watchlist_items, &(&1.id == item_id))
        {:noreply, assign(socket, :watchlist_items, items)}
    end
  end

  def handle_event("unfavorite", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    video = %{id: video_id}

    case Engagement.toggle_favorite(org, viewer, video) do
      {:ok, _id, :removed} ->
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

  def handle_event("reorder_queue", %{"ordered_ids" => ids}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    Engagement.reorder_queue(org, viewer, ids)
    %{results: queue_items} = Engagement.list_queue(org, viewer, per_page: 100)
    {:noreply, assign(socket, :queue_items, queue_items)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    path = tab_path(tab)
    {:noreply, push_patch(socket, to: path)}
  end

  defp tab_path("favorites"), do: "/favorites"
  defp tab_path("queue"), do: "/queue"
  defp tab_path(_), do: "/watchlist"

  defp find_watchlist_item(items, id), do: Enum.find(items, &(&1.id == id))

  defp watchlist_item_target(%{item_type: :video, video: %{} = video}), do: video
  defp watchlist_item_target(%{item_type: :season, season: %{} = season}), do: season
  defp watchlist_item_target(%{item_type: :series, series: %{} = series}), do: series
  defp watchlist_item_target(_), do: nil

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
            :if={@watchlist_items == []}
            title="Your watchlist is empty"
            description="Browse content to add videos."
            icon="hero-bookmark"
          >
            <.link navigate="/browse" class="sv-btn sv-btn-accent" style="margin-top: 16px">
              Browse content
            </.link>
          </ViewerComponents.empty_state>

          <div
            :if={@watchlist_items != []}
            class="sv-browse-grid"
            data-test="sv-watchlist-grid"
          >
            <div
              :for={item <- @watchlist_items}
              :if={watchlist_item_target(item)}
              class="sv-library-card-wrapper"
              data-test={"sv-watchlist-item-#{item.id}"}
            >
              <%= case item.item_type do %>
                <% :video -> %>
                  <ViewerComponents.content_card
                    video={item.video}
                    size="grid"
                    current_viewer={@current_viewer}
                    favorited_ids={@favorited_ids}
                    watchlisted_ids={@watchlisted_ids}
                    queued_ids={@queued_ids}
                  />
                  <button
                    disabled={readonly_sample?(@current_viewer)}
                    title={
                      if readonly_sample?(@current_viewer), do: "Sample member preview is read-only"
                    }
                    phx-click="remove"
                    phx-value-video-id={item.video.id}
                    class="sv-btn sv-btn-ghost sv-library-action-btn"
                    data-test={"sv-watchlist-remove-#{item.video.id}"}
                  >
                    <.icon name="hero-x-mark" class="size-4 mr-1" aria-hidden="true" /> Remove
                  </button>
                <% :season -> %>
                  <ViewerComponents.season_card season={item.season} size="grid" />
                  <button
                    disabled={readonly_sample?(@current_viewer)}
                    title={
                      if readonly_sample?(@current_viewer), do: "Sample member preview is read-only"
                    }
                    phx-click="remove_watchlist_item"
                    phx-value-item-id={item.id}
                    class="sv-btn sv-btn-ghost sv-library-action-btn"
                    data-test={"sv-watchlist-remove-season-#{item.season.id}"}
                  >
                    <.icon name="hero-x-mark" class="size-4 mr-1" aria-hidden="true" /> Remove
                  </button>
                <% :series -> %>
                  <ViewerComponents.series_card series={item.series} size="grid" />
                  <button
                    disabled={readonly_sample?(@current_viewer)}
                    title={
                      if readonly_sample?(@current_viewer), do: "Sample member preview is read-only"
                    }
                    phx-click="remove_watchlist_item"
                    phx-value-item-id={item.id}
                    class="sv-btn sv-btn-ghost sv-library-action-btn"
                    data-test={"sv-watchlist-remove-series-#{item.series.id}"}
                  >
                    <.icon name="hero-x-mark" class="size-4 mr-1" aria-hidden="true" /> Remove
                  </button>
              <% end %>
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
            <div :for={fav <- @favorites} :if={fav.video} class="sv-library-card-wrapper">
              <ViewerComponents.content_card
                video={fav.video}
                size="grid"
                current_viewer={@current_viewer}
                favorited_ids={@favorited_ids}
                watchlisted_ids={@watchlisted_ids}
                queued_ids={@queued_ids}
              />
              <button
                disabled={readonly_sample?(@current_viewer)}
                title={if readonly_sample?(@current_viewer), do: "Sample member preview is read-only"}
                phx-click="unfavorite"
                phx-value-video-id={fav.video_id}
                class="sv-btn sv-btn-ghost sv-library-action-btn"
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

          <div
            :if={@queue_items != []}
            id="queue-page-list"
            phx-hook="QueueSortable"
            class="sv-queue-page-list"
            data-test="sv-queue-list"
          >
            <div
              :for={{item, index} <- Enum.with_index(@queue_items)}
              :if={item.video}
              class={["sv-queue-page-item", index == 0 && "next-up"]}
              data-id={item.video_id}
              data-test={"sv-queue-item-#{item.video_id}"}
            >
              <div class="sv-queue-drag-handle" data-test="queue-drag-handle" aria-hidden="true">
                <.icon name="hero-bars-3" class="size-5" />
              </div>
              <.link
                navigate={~p"/watch/#{item.video_id}"}
                class="sv-queue-page-item-link"
                data-test={"sv-queue-link-#{item.video_id}"}
              >
                <img
                  :if={item.video.mux_playback_id}
                  src={"https://image.mux.com/#{item.video.mux_playback_id}/thumbnail.webp?width=320&height=180&fit_mode=smartcrop"}
                  alt={item.video.title}
                  class="sv-queue-page-thumb"
                />
                <div class="sv-queue-page-item-info">
                  <span class="sv-queue-page-item-title">{item.video.title}</span>
                  <span :if={item.video.duration} class="sv-queue-page-item-duration">
                    {format_duration(item.video.duration)}
                  </span>
                </div>
              </.link>
              <button
                disabled={readonly_sample?(@current_viewer)}
                title={if readonly_sample?(@current_viewer), do: "Sample member preview is read-only"}
                phx-click="remove_from_queue"
                phx-value-video-id={item.video_id}
                class="sv-queue-page-remove"
                data-test={"sv-queue-remove-#{item.video_id}"}
                aria-label={"Remove #{item.video.title} from queue"}
              >
                <.icon name="hero-x-mark" class="size-5" aria-hidden="true" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end

  defp readonly_sample?(%{__impersonating__: true, metadata: %{"admin_demo_sample" => true}}),
    do: true

  defp readonly_sample?(_), do: false
end
