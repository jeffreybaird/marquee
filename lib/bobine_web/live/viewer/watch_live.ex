# NOTE: Convert to static page with LiveView island for the player
defmodule BobineWeb.Viewer.WatchLive do
  @moduledoc """
  Video player page for subscribed viewers.

  Handles Mux playback, resume position, queue panel with drag-and-drop
  reordering, related videos grid, and engagement actions (favorite,
  watchlist, queue) via CardActions.

  Hooks: MuxPlayer, PlaybackTracker, QueueSortable, CardFocus, RowScroller
  Events: playback_started, playback_progress, playback_paused, progress_update,
          reorder_queue, card_toggle_favorite, card_add_to_watchlist, card_add_to_queue
  Route: /watch/:id (viewer_subscribed session)
  """

  use BobineWeb, :live_view
  use BobineWeb.Viewer.CardActions

  import BobineWeb.Viewer.WatchLive.Components

  alias Bobine.Content
  alias Bobine.Content.AccessControl
  alias Bobine.Engagement
  alias Bobine.Metrics
  alias BobineWeb.Components.ViewerComponents
  alias BobineWeb.Components.ViewerLayout

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    mount_started_at = System.monotonic_time()
    org = socket.assigns.organization
    viewer = socket.assigns[:current_viewer]
    scope = socket.assigns[:current_scope]

    {video_db_duration_ms, video_result} = timed(fn -> Content.get_video(org, id) end)

    case video_result do
      {:ok, %{mux_status: "ready"} = video} ->
        if AccessControl.can_watch?(video, viewer) do
          mount_video(
            socket,
            video,
            viewer,
            scope,
            org,
            mount_started_at,
            1,
            video_db_duration_ms
          )
        else
          emit_watch_mount_metric(
            org.id,
            socket,
            :denied,
            mount_started_at,
            1,
            video_db_duration_ms
          )

          handle_access_denied(socket, video, viewer)
        end

      {:ok, _video} ->
        emit_watch_mount_metric(
          org.id,
          socket,
          :redirect,
          mount_started_at,
          1,
          video_db_duration_ms
        )

        {:ok, push_navigate(socket, to: ~p"/")}

      {:error, :not_found} ->
        emit_watch_mount_metric(
          org.id,
          socket,
          :not_found,
          mount_started_at,
          1,
          video_db_duration_ms
        )

        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  defp mount_video(
         socket,
         video,
         viewer,
         scope,
         org,
         mount_started_at,
         base_query_count,
         base_db_duration_ms
       ) do
    {watch_state_db_duration_ms, watch_state} =
      timed(fn -> build_watch_state(org, viewer, scope, video) end)

    related_result = Content.list_related_videos_for_watch(org, video, 6)

    query_count =
      base_query_count + watch_state_query_count(viewer, scope) + related_result.query_count

    db_duration_ms =
      base_db_duration_ms + watch_state_db_duration_ms + related_result.db_duration_ms

    if connected?(socket) do
      Metrics.video_viewed(org.id, video.id)
    end

    emit_watch_mount_metric(
      org.id,
      socket,
      :ok,
      mount_started_at,
      query_count,
      db_duration_ms
    )

    {:ok,
     assign(socket,
       video: video,
       page_title: video.title,
       resume_position: watch_state.resume_position,
       related_videos: related_result.videos,
       queue_items: [],
       queue_count: watch_state.queue_count,
       queue_loaded?: false,
       queue_open: false,
       is_favorited: watch_state.is_favorited,
       in_watchlist: watch_state.in_watchlist,
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
    Metrics.watch_event(socket.assigns.organization.id, "playback_started")
    {:noreply, socket}
  end

  @impl true
  def handle_event("playback_progress", %{"video_id" => video_id, "position" => pos}, socket) do
    Metrics.watch_event(socket.assigns.organization.id, "playback_progress")
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
    Metrics.watch_event(socket.assigns.organization.id, "playback_paused")
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
    Metrics.watch_event(socket.assigns.organization.id, "playback_ended")
    viewer = socket.assigns[:current_viewer]
    org = socket.assigns.organization

    if viewer do
      Engagement.mark_completed(org, viewer, socket.assigns.video)
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
    video = current_or_load_video(socket, video_id)

    case Engagement.add_to_queue(org, viewer, video) do
      {:ok, _} ->
        {:noreply, refresh_queue(socket, open?: true)}

      {:error, :already_in_queue} ->
        {:noreply, put_flash(socket, :info, "Already in your queue.")}
    end
  end

  @impl true
  def handle_event("play_next", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    video = current_or_load_video(socket, video_id)

    Engagement.play_next(org, viewer, video)
    {:noreply, refresh_queue(socket, open?: true)}
  end

  @impl true
  def handle_event("remove_from_queue", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    video = current_or_load_video(socket, video_id)

    Engagement.remove_from_queue(org, viewer, video)
    {:noreply, refresh_queue(socket)}
  end

  @impl true
  def handle_event("reorder_queue", %{"ordered_ids" => ids}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    Engagement.reorder_queue(org, viewer, ids)
    {:noreply, refresh_queue(socket)}
  end

  @impl true
  def handle_event("clear_queue", _params, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    Engagement.clear_queue(org, viewer)

    {:noreply,
     assign(socket, queue_items: [], queue_count: 0, queue_loaded?: true, queue_open: false)}
  end

  @impl true
  def handle_event("toggle_queue", _params, socket) do
    socket =
      if socket.assigns.queue_open do
        assign(socket, queue_open: false)
      else
        socket
        |> ensure_queue_loaded()
        |> assign(queue_open: true)
      end

    {:noreply, socket}
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
        watch_state = build_watch_state(org, viewer, socket.assigns.current_scope, prev_video)
        queue_items = Engagement.list_queue(org, viewer)

        if socket.assigns[:go_back_timer], do: Process.cancel_timer(socket.assigns.go_back_timer)

        socket =
          socket
          |> assign(
            video: prev_video,
            resume_position: position,
            related_videos: Content.list_related_videos_for_watch(org, prev_video, 6).videos,
            queue_items: queue_items,
            queue_count: length(queue_items),
            queue_loaded?: true,
            queue_open: true,
            page_title: prev_video.title,
            is_favorited: watch_state.is_favorited,
            in_watchlist: watch_state.in_watchlist,
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
    {:noreply, refresh_queue(socket, open?: true)}
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
    video = current_or_load_video(socket, video_id)

    case Engagement.advance_queue(org, viewer, video) do
      {:ok, %{next_video: next_video}} when not is_nil(next_video) ->
        watch_state = build_watch_state(org, viewer, socket.assigns.current_scope, next_video)
        queue_items = Engagement.list_queue(org, viewer)

        if socket.assigns[:go_back_timer], do: Process.cancel_timer(socket.assigns.go_back_timer)
        timer = Process.send_after(self(), :go_back_expired, 60_000)

        socket =
          socket
          |> assign(
            video: next_video,
            resume_position: watch_state.resume_position,
            related_videos: Content.list_related_videos_for_watch(org, next_video, 6).videos,
            queue_items: queue_items,
            queue_count: length(queue_items),
            queue_loaded?: true,
            queue_open: true,
            page_title: next_video.title,
            is_favorited: watch_state.is_favorited,
            in_watchlist: watch_state.in_watchlist,
            go_back_available: true,
            go_back_timer: timer
          )
          |> push_event("play_next_in_queue", %{
            playback_id: next_video.mux_playback_id,
            video_id: next_video.id,
            resume_position: watch_state.resume_position
          })

        {:noreply, socket}

      {:ok, %{next_video: nil}} ->
        if socket.assigns[:go_back_timer], do: Process.cancel_timer(socket.assigns.go_back_timer)
        timer = Process.send_after(self(), :go_back_expired, 60_000)

        {:noreply,
         assign(socket,
           queue_items: [],
           queue_count: 0,
           queue_loaded?: true,
           queue_open: false,
           go_back_available: true,
           go_back_timer: timer
         )}

      _ ->
        {:noreply, socket}
    end
  end

  defp build_watch_state(org, viewer, scope, video) do
    cond do
      viewer && !Map.get(viewer, :__impersonating__, false) ->
        Engagement.get_watch_session_state(org, viewer, video)

      scope && scope.user ->
        progress = Engagement.get_progress(scope, video.id)

        %{
          resume_position: if(progress, do: progress.position, else: 0.0),
          queue_count: 0,
          is_favorited: false,
          in_watchlist: false
        }

      true ->
        %{resume_position: 0.0, queue_count: 0, is_favorited: false, in_watchlist: false}
    end
  end

  defp watch_state_query_count(%{__impersonating__: true}, scope) when not is_nil(scope), do: 1
  defp watch_state_query_count(viewer, _scope) when not is_nil(viewer), do: 1
  defp watch_state_query_count(_viewer, %{user: user}) when not is_nil(user), do: 1
  defp watch_state_query_count(_viewer, _scope), do: 0

  defp current_or_load_video(socket, video_id) do
    if socket.assigns.video.id == video_id do
      socket.assigns.video
    else
      Content.get_video!(video_id)
    end
  end

  defp ensure_queue_loaded(socket) do
    if socket.assigns.queue_loaded? do
      socket
    else
      refresh_queue(socket)
    end
  end

  defp refresh_queue(socket, opts \\ []) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    queue_items = Engagement.list_queue(org, viewer)

    assign(socket,
      queue_items: queue_items,
      queue_count: length(queue_items),
      queue_loaded?: true,
      queue_open: Keyword.get(opts, :open?, socket.assigns.queue_open)
    )
  end

  defp emit_watch_mount_metric(org_id, socket, status, started_at, query_count, db_duration_ms) do
    duration_ms =
      System.convert_time_unit(System.monotonic_time() - started_at, :native, :millisecond)

    phase = if connected?(socket), do: :connected, else: :disconnected
    Metrics.watch_mount(org_id, phase, status, duration_ms, query_count, db_duration_ms)
  end

  defp timed(fun) do
    started_at = System.monotonic_time()
    result = fun.()

    duration_ms =
      System.convert_time_unit(System.monotonic_time() - started_at, :native, :millisecond)

    {duration_ms, result}
  end
end
