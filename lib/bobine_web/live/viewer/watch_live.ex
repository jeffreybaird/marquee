# NOTE: Convert to static page with LiveView island for the player
defmodule BobineWeb.Viewer.WatchLive do
  use BobineWeb, :live_view

  alias Bobine.Content
  alias Bobine.Content.AccessControl
  alias Bobine.Engagement
  alias BobineWeb.Components.ViewerComponents
  alias BobineWeb.Components.ViewerLayout

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns[:current_viewer]
    scope = socket.assigns[:current_scope]

    case Content.get_video(org, id) do
      {:ok, %{mux_status: "ready"} = video} ->
        if AccessControl.can_watch?(video, viewer) do
          mount_video(socket, video, viewer, scope, org)
        else
          handle_access_denied(socket, video, viewer)
        end

      {:ok, _video} ->
        {:ok, push_navigate(socket, to: ~p"/")}

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  defp mount_video(socket, video, viewer, scope, org) do
    # Try viewer progress first, fall back to operator progress
    progress =
      cond do
        viewer && !Map.get(viewer, :__impersonating__, false) ->
          Engagement.get_progress(org, viewer, video)

        scope && scope.user ->
          Engagement.get_progress(scope, video.id)

        true ->
          nil
      end

    resume_position = if progress, do: progress.position, else: 0.0

    # Load queue and engagement state for authenticated viewers
    {queue_items, is_favorited, in_watchlist} =
      if viewer do
        {
          Engagement.list_queue(org, viewer),
          Engagement.favorited?(org, viewer, video),
          Engagement.in_watchlist?(org, viewer, video)
        }
      else
        {[], false, false}
      end

    # Load related content
    %{results: related} = Content.list_videos(org, per_page: 12)
    related = Enum.reject(related, &(&1.id == video.id)) |> Enum.take(8)

    if connected?(socket) do
      Bobine.Metrics.video_viewed(org.id, video.id)
    end

    {:ok,
     assign(socket,
       video: video,
       page_title: video.title,
       resume_position: resume_position,
       related_videos: related,
       queue_items: queue_items,
       queue_open: queue_items != [],
       is_favorited: is_favorited,
       in_watchlist: in_watchlist,
       go_back_available: false,
       go_back_timer: nil
     )}
  end

  defp handle_access_denied(socket, _video, viewer) do
    if is_nil(viewer) do
      {:ok, push_navigate(socket, to: ~p"/login")}
    else
      {:ok, push_navigate(socket, to: ~p"/subscribe")}
    end
  end

  ## -----------------------------------------------------------------------
  ## Playback events
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("playback_started", %{"video_id" => _id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("playback_progress", %{"video_id" => video_id, "position" => pos}, socket) do
    viewer = socket.assigns[:current_viewer]
    org = socket.assigns.organization

    if viewer do
      video = socket.assigns.video
      duration = video.duration || 0.0
      Engagement.update_progress(org, viewer, video_id, pos, duration)
    else
      scope = socket.assigns.current_scope

      if scope && scope.user do
        Engagement.update_progress(scope, video_id, pos)
      end
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("playback_paused", %{"video_id" => video_id, "position" => pos}, socket) do
    viewer = socket.assigns[:current_viewer]
    org = socket.assigns.organization

    if viewer do
      video = socket.assigns.video
      duration = video.duration || 0.0
      Engagement.update_progress(org, viewer, video_id, pos, duration)
    else
      scope = socket.assigns.current_scope

      if scope && scope.user do
        Engagement.update_progress(scope, video_id, pos)
      end
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("playback_ended", %{"video_id" => video_id}, socket) do
    viewer = socket.assigns[:current_viewer]

    if viewer do
      advance_to_next(socket, video_id)
    else
      {:noreply, socket}
    end
  end

  ## -----------------------------------------------------------------------
  ## Queue actions
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("add_to_queue", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    video = Content.get_video!(video_id)

    case Engagement.add_to_queue(org, viewer, video) do
      {:ok, _} ->
        queue_items = Engagement.list_queue(org, viewer)
        {:noreply, assign(socket, queue_items: queue_items, queue_open: true)}

      {:error, :already_in_queue} ->
        {:noreply, put_flash(socket, :info, "Already in your queue.")}
    end
  end

  @impl true
  def handle_event("play_next", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    video = Content.get_video!(video_id)

    Engagement.play_next(org, viewer, video)
    queue_items = Engagement.list_queue(org, viewer)
    {:noreply, assign(socket, queue_items: queue_items, queue_open: true)}
  end

  @impl true
  def handle_event("remove_from_queue", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    video = Content.get_video!(video_id)

    Engagement.remove_from_queue(org, viewer, video)
    queue_items = Engagement.list_queue(org, viewer)
    {:noreply, assign(socket, queue_items: queue_items)}
  end

  @impl true
  def handle_event("reorder_queue", %{"ordered_ids" => ids}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    Engagement.reorder_queue(org, viewer, ids)
    queue_items = Engagement.list_queue(org, viewer)
    {:noreply, assign(socket, queue_items: queue_items)}
  end

  @impl true
  def handle_event("clear_queue", _params, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    Engagement.clear_queue(org, viewer)
    {:noreply, assign(socket, queue_items: [], queue_open: false)}
  end

  @impl true
  def handle_event("toggle_queue", _params, socket) do
    {:noreply, assign(socket, queue_open: !socket.assigns.queue_open)}
  end

  @impl true
  def handle_event("skip_to_next", _params, socket) do
    advance_to_next(socket, socket.assigns.video.id)
  end

  @impl true
  def handle_event("go_back", _params, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    case Engagement.go_back_in_queue(org, viewer) do
      {:ok, %{video: prev_video, resume_position: position}} ->
        queue_items = Engagement.list_queue(org, viewer)

        if socket.assigns[:go_back_timer], do: Process.cancel_timer(socket.assigns.go_back_timer)

        socket =
          socket
          |> assign(
            video: prev_video,
            queue_items: queue_items,
            page_title: prev_video.title,
            go_back_available: false,
            go_back_timer: nil
          )
          |> push_event("play_next_in_queue", %{
            playback_id: prev_video.mux_playback_id,
            video_id: prev_video.id,
            resume_position: position
          })

        {:noreply, socket}

      {:error, _} ->
        {:noreply, assign(socket, go_back_available: false)}
    end
  end

  ## -----------------------------------------------------------------------
  ## Collection queue
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("add_collection_to_queue", %{"collection-id" => collection_id}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    Engagement.add_collection_to_queue(org, viewer, %{id: collection_id})
    queue_items = Engagement.list_queue(org, viewer)
    {:noreply, assign(socket, queue_items: queue_items, queue_open: true)}
  end

  ## -----------------------------------------------------------------------
  ## Favorites and watchlist toggles
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("toggle_favorite", _params, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    video = socket.assigns.video

    case Engagement.toggle_favorite(org, viewer, video) do
      {:ok, :added} -> {:noreply, assign(socket, is_favorited: true)}
      {:ok, :removed} -> {:noreply, assign(socket, is_favorited: false)}
    end
  end

  @impl true
  def handle_event("toggle_watchlist", _params, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    video = socket.assigns.video

    if socket.assigns.in_watchlist do
      Engagement.remove_from_watchlist(org, viewer, video)
      {:noreply, assign(socket, in_watchlist: false)}
    else
      Engagement.add_to_watchlist(org, viewer, video)
      {:noreply, assign(socket, in_watchlist: true)}
    end
  end

  ## -----------------------------------------------------------------------
  ## Go-back timer
  ## -----------------------------------------------------------------------

  @impl true
  def handle_info(:go_back_expired, socket) do
    {:noreply, assign(socket, go_back_available: false, go_back_timer: nil)}
  end

  ## -----------------------------------------------------------------------
  ## Private — advance to next in queue
  ## -----------------------------------------------------------------------

  defp advance_to_next(socket, video_id) do
    viewer = socket.assigns.current_viewer
    org = socket.assigns.organization
    video = Content.get_video!(video_id)

    case Engagement.advance_queue(org, viewer, video) do
      {:ok, %{next_video: next_video}} when not is_nil(next_video) ->
        progress = Engagement.get_progress(org, viewer, next_video)
        queue_items = Engagement.list_queue(org, viewer)

        if socket.assigns[:go_back_timer], do: Process.cancel_timer(socket.assigns.go_back_timer)
        timer = Process.send_after(self(), :go_back_expired, 60_000)

        socket =
          socket
          |> assign(
            video: next_video,
            queue_items: queue_items,
            page_title: next_video.title,
            go_back_available: true,
            go_back_timer: timer
          )
          |> push_event("play_next_in_queue", %{
            playback_id: next_video.mux_playback_id,
            video_id: next_video.id,
            resume_position: (progress && progress.position) || 0.0
          })

        {:noreply, socket}

      {:ok, %{next_video: nil}} ->
        if socket.assigns[:go_back_timer], do: Process.cancel_timer(socket.assigns.go_back_timer)
        timer = Process.send_after(self(), :go_back_expired, 60_000)

        {:noreply, assign(socket, queue_items: [], go_back_available: true, go_back_timer: timer)}

      _ ->
        {:noreply, socket}
    end
  end

  ## -----------------------------------------------------------------------
  ## Render
  ## -----------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path={~p"/watch/#{@video.id}"}
      theme={@theme}
      flash={@flash}
    >
      <div class="sv-watch-layout">
        <div class="sv-watch-main">
          <%!-- Player --%>
          <ViewerComponents.video_player
            video={@video}
            resume_position={@resume_position}
          />

          <%!-- Video metadata --%>
          <div class="sv-video-meta">
            <h1 class="sv-video-title" data-test="video-title">{@video.title}</h1>

            <div :if={@video.duration} class="sv-video-badges">
              <ViewerComponents.badge label={format_duration(@video.duration)} />
            </div>

            <p
              :if={@video.description}
              class="sv-video-desc"
              data-test="video-description"
            >
              {@video.description}
            </p>

            <div class="sv-video-actions" data-test="video-actions">
              <%!-- Queue navigation --%>
              <button
                :if={@current_viewer && @queue_items != []}
                phx-click="skip_to_next"
                class="sv-btn sv-btn-secondary"
                data-test="skip-next-btn"
                aria-label="Skip to next video in queue"
              >
                <.icon name="hero-forward" class="size-5 mr-1" aria-hidden="true" /> Next
              </button>

              <button
                :if={@go_back_available}
                phx-click="go_back"
                class="sv-btn sv-btn-secondary sv-go-back-btn"
                data-test="go-back-btn"
                aria-label="Go back to previous video"
              >
                <.icon name="hero-backward" class="size-5 mr-1" aria-hidden="true" /> Go back
              </button>

              <%!-- Engagement actions --%>
              <button
                :if={@current_viewer}
                phx-click="add_to_queue"
                phx-value-video-id={@video.id}
                class="sv-btn sv-btn-secondary"
                data-test="add-to-queue-btn"
                aria-label="Add to queue"
              >
                <.icon name="hero-queue-list" class="size-5 mr-1" aria-hidden="true" /> Queue
              </button>

              <button
                :if={@current_viewer}
                phx-click="play_next"
                phx-value-video-id={@video.id}
                class="sv-btn sv-btn-secondary"
                data-test="play-next-btn"
                aria-label="Play next in queue"
              >
                <.icon name="hero-play" class="size-5 mr-1" aria-hidden="true" /> Play next
              </button>

              <button
                :if={@current_viewer}
                phx-click="toggle_favorite"
                class={["sv-btn sv-btn-secondary", @is_favorited && "active"]}
                data-test="favorite-btn"
                aria-label={if @is_favorited, do: "Remove from favorites", else: "Add to favorites"}
              >
                <.icon
                  name={if @is_favorited, do: "hero-heart-solid", else: "hero-heart"}
                  class="size-5 mr-1"
                  aria-hidden="true"
                /> Favorite
              </button>

              <button
                :if={@current_viewer}
                phx-click="toggle_watchlist"
                class={["sv-btn sv-btn-secondary", @in_watchlist && "active"]}
                data-test="watchlist-btn"
                aria-label={if @in_watchlist, do: "Remove from watchlist", else: "Add to watchlist"}
              >
                <.icon
                  name={if @in_watchlist, do: "hero-bookmark-solid", else: "hero-bookmark"}
                  class="size-5 mr-1"
                  aria-hidden="true"
                /> Watchlist
              </button>
            </div>
          </div>

          <%!-- Related content --%>
          <div :if={@related_videos != []} class="sv-row" style="margin-top: 48px;">
            <h2 class="sv-row-title">More from {@organization.name}</h2>
            <div class="sv-browse-grid">
              <ViewerComponents.content_card
                :for={video <- @related_videos}
                video={video}
                size="grid"
              />
            </div>
          </div>
        </div>

        <%!-- Queue panel --%>
        <aside
          :if={@current_viewer}
          class={["sv-queue-panel", @queue_open && "open"]}
          data-test="queue-panel"
        >
          <div class="sv-queue-header">
            <h3>Queue ({length(@queue_items)})</h3>
            <button
              phx-click="toggle_queue"
              class="sv-btn sv-btn-ghost"
              data-test="toggle-queue-btn"
              aria-label={if @queue_open, do: "Close queue", else: "Open queue"}
            >
              <.icon name="hero-x-mark" class="size-5" aria-hidden="true" />
            </button>
          </div>

          <div
            :if={@queue_items != []}
            id="queue-list"
            phx-hook="QueueSortable"
            class="sv-queue-list"
            data-test="queue-list"
          >
            <div
              :for={{item, index} <- Enum.with_index(@queue_items)}
              class={["sv-queue-item", index == 0 && "next-up"]}
              data-id={item.video_id}
              data-test={"queue-item-#{item.video_id}"}
            >
              <div class="sv-queue-drag-handle" data-test="queue-drag-handle" aria-hidden="true">
                <.icon name="hero-bars-3" class="size-4" />
              </div>
              <img
                :if={item.video && item.video.mux_playback_id}
                src={"https://image.mux.com/#{item.video.mux_playback_id}/thumbnail.webp?width=160&height=90&fit_mode=smartcrop"}
                alt={item.video.title}
                class="sv-queue-thumb"
              />
              <div class="sv-queue-item-info">
                <span class="sv-queue-item-title">{item.video.title}</span>
                <span :if={item.video.duration} class="sv-queue-item-duration">
                  {format_duration(item.video.duration)}
                </span>
              </div>
              <button
                phx-click="remove_from_queue"
                phx-value-video-id={item.video_id}
                class="sv-queue-remove"
                data-test={"queue-remove-#{item.video_id}"}
                aria-label={"Remove #{item.video.title} from queue"}
              >
                <.icon name="hero-x-mark" class="size-4" aria-hidden="true" />
              </button>
            </div>
          </div>

          <div :if={@queue_items != []} class="sv-queue-footer">
            <button
              phx-click="clear_queue"
              class="sv-btn sv-btn-ghost"
              style="width: 100%"
              data-test="clear-queue-btn"
            >
              Clear queue
            </button>
          </div>

          <div :if={@queue_items == []} class="sv-queue-empty" data-test="queue-empty">
            <p>Your queue is empty</p>
            <p>Browse content and add videos to build your watch queue.</p>
          </div>
        </aside>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end

  defp format_duration(nil), do: ""

  defp format_duration(seconds) when is_number(seconds) do
    minutes = div(trunc(seconds), 60)
    secs = rem(trunc(seconds), 60)

    if minutes >= 60 do
      hours = div(minutes, 60)
      mins = rem(minutes, 60)
      "#{hours}h #{mins}m"
    else
      "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
    end
  end

  defp format_duration(_), do: ""
end
