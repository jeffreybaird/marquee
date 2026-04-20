# NOTE: Convert to static page with LiveView island for the player
defmodule BobineWeb.Viewer.WatchLive do
  @moduledoc """
  Unified video player page for subscribed viewers.

  Handles standalone video playback, series/season navigation, Mux playback,
  resume position, queue panel with drag-and-drop reordering, related videos
  grid, and engagement actions (favorite, watchlist, queue) via CardActions.

  Routes:
    - /watch/:id           — direct video playback (standalone or episode)
    - /series/:slug        — series entry, picks best episode for viewer
    - /series/:slug/season/:season_number — specific season entry

  Hooks: MuxPlayer, PlaybackTracker, QueueSortable, CardFocus, RowScroller,
         ScrollToCurrentEpisode
  Events: playback_started, playback_progress, playback_paused, progress_update,
          reorder_queue, card_toggle_favorite, card_add_to_watchlist,
          card_add_to_queue, switch_season, play_episode, playback_ended
  """

  use BobineWeb, :live_view
  use BobineWeb.Viewer.CardActions

  import BobineWeb.Viewer.WatchLive.Components

  alias Bobine.Content
  alias Bobine.Content.AccessControl
  alias Bobine.Engagement
  alias Bobine.Events
  alias Bobine.Metrics
  alias BobineWeb.Components.ViewerComponents
  alias BobineWeb.Components.ViewerLayout

  @impl true
  def mount(params, _session, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns[:current_viewer]

    case socket.assigns.live_action do
      action when action in [nil, :index] ->
        mount_direct_video(params, org, viewer, socket)

      action when action in [:series, :series_season] ->
        mount_series(params, org, viewer, socket)
    end
  end

  ## -----------------------------------------------------------------------
  ## Mount — direct video (/watch/:id)
  ## -----------------------------------------------------------------------

  defp mount_direct_video(%{"id" => id}, org, viewer, socket) do
    mount_started_at = System.monotonic_time()
    scope = socket.assigns[:current_scope]

    {video_db_duration_ms, video_result} = timed(fn -> Content.get_video(org, id) end)

    case video_result do
      {:ok, %{mux_status: "ready"} = video} ->
        if AccessControl.can_watch?(video, viewer) do
          mount_ready_video(
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

  defp mount_ready_video(
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

    related_result = Content.list_related_videos_for_watch(org, video, 8)

    query_count =
      base_query_count + watch_state_query_count(viewer, scope) + related_result.query_count

    db_duration_ms =
      base_db_duration_ms + watch_state_db_duration_ms + related_result.db_duration_ms

    if connected?(socket) do
      Metrics.video_viewed(org.id, video.id)
      subscribe_to_queue_events(org, viewer)
    end

    emit_watch_mount_metric(
      org.id,
      socket,
      :ok,
      mount_started_at,
      query_count,
      db_duration_ms
    )

    # Check if this video is an episode — if so, load season context
    episode_context = Content.get_episode_context(org, video)

    season_assigns =
      if episode_context do
        build_season_assigns(org, viewer, episode_context)
      else
        standalone_assigns()
      end

    {:ok,
     assign(
       socket,
       Map.merge(season_assigns, %{
         video: video,
         episode_context: episode_context,
         page_title: video.title,
         resume_position: watch_state.resume_position,
         related_videos: related_result.videos,
         queue_items: [],
         queue_count: watch_state.queue_count,
         queue_loaded?: false,
         queue_open: false,
         queue_dropdown_open: nil,
         queue_season_confirm: nil,
         is_favorited: watch_state.is_favorited,
         in_watchlist: watch_state.in_watchlist,
         go_back_available: false,
         go_back_timer: nil
       })
     )}
  end

  ## -----------------------------------------------------------------------
  ## Mount — series entry (/series/:slug, /series/:slug/season/:number)
  ## -----------------------------------------------------------------------

  defp mount_series(params, org, viewer, socket) do
    slug = params["slug"]

    with {:ok, series} <- Content.get_series_by_slug(org, slug),
         %{results: [_ | _] = season_results} = seasons <- Content.list_seasons(org, series),
         selected_season <- resolve_season(params, org, viewer, season_results),
         [_ | _] = episodes <- Content.list_episodes(org, selected_season) do
      mount_series_episode(socket, org, viewer, series, selected_season, seasons, episodes)
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  defp mount_series_episode(socket, org, viewer, series, selected_season, seasons, episodes) do
    scope = socket.assigns[:current_scope]
    video = resolve_episode_video(org, viewer, episodes)
    episode_context = Content.get_episode_context(org, video)
    watch_state = build_watch_state(org, viewer, scope, video)

    viewer_progress = build_viewer_progress(org, viewer, episodes)

    if connected?(socket), do: subscribe_to_queue_events(org, viewer)

    {:ok,
     assign(socket,
       video: video,
       episode_context: episode_context,
       episodes: episodes,
       seasons: seasons.results,
       selected_season: selected_season,
       viewer_progress: viewer_progress,
       playback_mode: :collection,
       page_title: "#{series.title} — #{selected_season.title}",
       resume_position: watch_state.resume_position,
       related_videos: [],
       queue_items: [],
       queue_count: watch_state.queue_count,
       queue_loaded?: false,
       queue_open: false,
       queue_dropdown_open: nil,
       queue_season_confirm: nil,
       is_favorited: watch_state.is_favorited,
       in_watchlist: watch_state.in_watchlist,
       go_back_available: false,
       go_back_timer: nil
     )}
  end

  ## -----------------------------------------------------------------------
  ## Season/episode resolution helpers
  ## -----------------------------------------------------------------------

  defp resolve_season(params, org, viewer, seasons) do
    cond do
      params["season_number"] ->
        number = String.to_integer(params["season_number"])
        Enum.find(seasons, List.first(seasons), &(&1.season_number == number))

      viewer ->
        find_active_season(org, viewer, seasons) || List.first(seasons)

      true ->
        List.first(seasons)
    end
  end

  defp find_active_season(org, viewer, seasons) do
    Enum.find(seasons, fn season ->
      season
      |> then(&Content.list_episodes(org, &1))
      |> Enum.any?(&episode_in_progress?(org, viewer, &1))
    end)
  end

  defp episode_in_progress?(org, viewer, episode) do
    case Engagement.get_progress(org, viewer, episode.video) do
      %{completed: false} -> true
      _ -> false
    end
  end

  defp resolve_episode_video(_org, nil, episodes), do: List.first(episodes).video

  defp resolve_episode_video(org, viewer, episodes) do
    in_progress = Enum.find(episodes, &episode_resumable?(org, viewer, &1))
    unwatched = Enum.find(episodes, &episode_unwatched?(org, viewer, &1))

    chosen = in_progress || unwatched || List.first(episodes)
    chosen.video
  end

  defp episode_resumable?(org, viewer, episode) do
    case Engagement.get_progress(org, viewer, episode.video) do
      %{completed: false, position: pos} when pos > 0 -> true
      _ -> false
    end
  end

  defp episode_unwatched?(org, viewer, episode) do
    Engagement.get_progress(org, viewer, episode.video) == nil
  end

  ## -----------------------------------------------------------------------
  ## Shared assign builders
  ## -----------------------------------------------------------------------

  defp build_season_assigns(org, viewer, episode_context) do
    episodes = Content.list_episodes(org, episode_context.season)
    seasons = Content.list_seasons(org, episode_context.series)

    viewer_progress = build_viewer_progress(org, viewer, episodes)

    %{
      episodes: episodes,
      seasons: seasons.results,
      selected_season: episode_context.season,
      viewer_progress: viewer_progress,
      playback_mode: :collection
    }
  end

  defp standalone_assigns do
    %{
      episodes: [],
      seasons: [],
      selected_season: nil,
      viewer_progress: %{},
      playback_mode: :standalone,
      episode_context: nil
    }
  end

  defp build_viewer_progress(org, viewer, episodes) do
    if viewer do
      episode_video_ids = Enum.map(episodes, & &1.video_id)
      Engagement.batch_get_progress(org, viewer, episode_video_ids)
    else
      %{}
    end
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
      clamped_pos = clamp_position(pos, duration)
      Engagement.update_progress(org, viewer, video_id, clamped_pos, duration)
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
      clamped_pos = clamp_position(pos, duration)
      Engagement.update_progress(org, viewer, video_id, clamped_pos, duration)
    else
      scope = socket.assigns.current_scope

      if scope && scope.user do
        Engagement.update_progress(scope, video_id, pos)
      end
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "playback_drop_off",
        %{"video_id" => video_id} = params,
        socket
      ) do
    Metrics.watch_event(socket.assigns.organization.id, "playback_drop_off")

    org = socket.assigns.organization
    viewer = socket.assigns[:current_viewer]
    scope = socket.assigns[:current_scope]

    subject_ids =
      cond do
        viewer -> %{viewer_id: viewer.id}
        scope && scope.user -> %{user_id: scope.user.id}
        true -> nil
      end

    if subject_ids do
      Engagement.record_drop_off(
        Map.merge(subject_ids, %{
          organization_id: org.id,
          video_id: video_id,
          max_position: Map.get(params, "max_position", 0.0),
          video_duration: Map.get(params, "video_duration")
        })
      )
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

      cond do
        # Queue takes precedence when it has items
        Engagement.queue_count(org, viewer) > 0 ->
          advance_to_next(socket, video_id)

        # Collection mode — advance to next episode in season
        socket.assigns.playback_mode == :collection && socket.assigns.episode_context ->
          handle_season_advance(socket, org, viewer)

        # Standalone or no queue — use existing queue advance (handles go-back)
        true ->
          advance_to_next(socket, video_id)
      end
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

  ## Targeted add: dispatched by the new dropdown that fires with
  ##   id    — the resource id (video or season)
  ##   type  — "video" | "season"
  ##   position — "beginning" | "end"
  ##
  ## A separate clause is used so the legacy single-click button keeps
  ## working without changes.
  @impl true
  def handle_event(
        "add_to_queue",
        %{"id" => id, "type" => type, "position" => position},
        socket
      ) do
    case type do
      "video" -> add_video_to_queue(socket, id, position)
      "season" -> dispatch_add_season_to_queue(socket, id, position)
    end
  end

  @impl true
  def handle_event(
        "toggle_queue_dropdown",
        %{"target-id" => target_id},
        socket
      ) do
    next =
      if socket.assigns.queue_dropdown_open == target_id, do: nil, else: target_id

    {:noreply, assign(socket, queue_dropdown_open: next)}
  end

  @impl true
  def handle_event("close_queue_dropdown", _params, socket) do
    {:noreply, assign(socket, queue_dropdown_open: nil)}
  end

  @impl true
  def handle_event("confirm_add_season", %{"mode" => mode}, socket) do
    %{season: season, position: position} = socket.assigns.queue_season_confirm
    do_add_season_to_queue(socket, season, position, String.to_atom(mode))
  end

  @impl true
  def handle_event("cancel_add_season", _params, socket) do
    {:noreply, assign(socket, queue_season_confirm: nil)}
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
        %{results: queue_items} = Engagement.list_queue(org, viewer, per_page: 100)

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
  ## Season switching and episode navigation
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("switch_season", %{"season_id" => season_id}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns[:current_viewer]
    season = Content.get_season!(org, season_id)
    episodes = Content.list_episodes(org, season)

    if episodes == [] do
      {:noreply, put_flash(socket, :info, "This season has no episodes yet.")}
    else
      video = resolve_episode_video(org, viewer, episodes)
      progress = get_viewer_progress(org, viewer, video)
      episode_context = Content.get_episode_context(org, video)

      viewer_progress = build_viewer_progress(org, viewer, episodes)

      socket =
        socket
        |> assign(
          video: video,
          episode_context: episode_context,
          episodes: episodes,
          selected_season: season,
          viewer_progress: viewer_progress,
          resume_position: (progress && progress.position) || 0.0,
          page_title: "#{episode_context.series.title} — #{season.title}"
        )
        |> push_event("play_next_in_queue", %{
          playback_id: video.mux_playback_id,
          video_id: video.id,
          resume_position: (progress && progress.position) || 0.0
        })

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("play_episode", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns[:current_viewer]

    case Content.get_video(org, video_id) do
      {:ok, video} ->
        progress = get_viewer_progress(org, viewer, video)
        episode_context = Content.get_episode_context(org, video)

        socket =
          socket
          |> assign(
            video: video,
            episode_context: episode_context,
            resume_position: (progress && progress.position) || 0.0,
            page_title: video.title
          )
          |> push_event("play_next_in_queue", %{
            playback_id: video.mux_playback_id,
            video_id: video.id,
            resume_position: (progress && progress.position) || 0.0
          })

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, socket}
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
      {:ok, _id, :added} -> {:noreply, assign(socket, is_favorited: true)}
      {:ok, _id, :removed} -> {:noreply, assign(socket, is_favorited: false)}
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

  def handle_info({:bobine_event, {event, %{viewer: %{id: vid}}}, _scope}, socket)
      when event in [:queue_item_added, :queue_item_removed, :queue_cleared] do
    if socket.assigns[:current_viewer] && socket.assigns.current_viewer.id == vid do
      {:noreply, refresh_queue(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:bobine_event, _event, _scope}, socket), do: {:noreply, socket}

  defp subscribe_to_queue_events(_org, nil), do: :ok
  defp subscribe_to_queue_events(org, _viewer), do: Events.subscribe(org.id)

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
        %{results: queue_items} = Engagement.list_queue(org, viewer, per_page: 100)

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

  ## -----------------------------------------------------------------------
  ## Private — targeted queue add (video / season dropdown)
  ## -----------------------------------------------------------------------

  defp add_video_to_queue(socket, video_id, position) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    video = current_or_load_video(socket, video_id)

    result =
      case position do
        "beginning" -> Engagement.play_next(org, viewer, video)
        _ -> Engagement.add_to_queue(org, viewer, video)
      end

    case result do
      {:ok, _} ->
        socket =
          socket
          |> assign(queue_dropdown_open: nil)
          |> refresh_queue(open?: true)

        {:noreply, socket}

      {:error, :already_in_queue} ->
        {:noreply,
         socket
         |> put_flash(:info, "Already in your queue.")
         |> assign(queue_dropdown_open: nil)}
    end
  end

  defp dispatch_add_season_to_queue(socket, season_id, position) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    season = Content.get_season!(org, season_id)

    if Engagement.has_season_progress?(org, viewer, season) do
      {:noreply,
       assign(socket,
         queue_season_confirm: %{season: season, position: position},
         queue_dropdown_open: nil
       )}
    else
      do_add_season_to_queue(socket, season, position, :all)
    end
  end

  defp do_add_season_to_queue(socket, season, position, mode) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    episodes = Content.list_episodes(org, season)

    videos_to_add = select_episodes_for_queue(org, viewer, episodes, mode)

    case position do
      "beginning" ->
        Engagement.add_videos_to_queue_beginning(org, viewer, videos_to_add)

      _ ->
        Engagement.add_videos_to_queue_end(org, viewer, videos_to_add)
    end

    socket =
      socket
      |> assign(queue_season_confirm: nil, queue_dropdown_open: nil)
      |> refresh_queue(open?: true)

    {:noreply, socket}
  end

  defp select_episodes_for_queue(_org, _viewer, episodes, :all) do
    Enum.map(episodes, & &1.video)
  end

  defp select_episodes_for_queue(org, viewer, episodes, :unwatched) do
    episodes
    |> Enum.reject(fn ep ->
      case Engagement.get_progress(org, viewer, ep.video) do
        %{completed: true} -> true
        _ -> false
      end
    end)
    |> Enum.map(& &1.video)
  end

  ## -----------------------------------------------------------------------
  ## Private — season auto-advance
  ## -----------------------------------------------------------------------

  defp handle_season_advance(socket, org, viewer) do
    video = socket.assigns.video

    case Content.next_episode(org, video) do
      nil ->
        advance_to_next_season(socket, org, viewer)

      next_ep ->
        switch_to_video(
          socket,
          org,
          viewer,
          next_ep.video,
          socket.assigns.selected_season,
          socket.assigns.episodes
        )
    end
  end

  defp advance_to_next_season(socket, org, viewer) do
    case Content.next_season(org, socket.assigns.selected_season) do
      nil ->
        {:noreply, assign(socket, playback_mode: :ended)}

      next_season ->
        episodes = Content.list_episodes(org, next_season)

        case List.first(episodes) do
          nil -> {:noreply, assign(socket, playback_mode: :ended)}
          first_ep -> switch_to_video(socket, org, viewer, first_ep.video, next_season, episodes)
        end
    end
  end

  defp switch_to_video(socket, org, viewer, video, season, episodes) do
    progress = get_viewer_progress(org, viewer, video)
    episode_context = Content.get_episode_context(org, video)
    viewer_progress = build_viewer_progress(org, viewer, episodes)

    socket =
      socket
      |> assign(
        video: video,
        episode_context: episode_context,
        episodes: episodes,
        selected_season: season,
        viewer_progress: viewer_progress,
        resume_position: (progress && progress.position) || 0.0,
        page_title: video.title
      )
      |> push_event("play_next_in_queue", %{
        playback_id: video.mux_playback_id,
        video_id: video.id,
        resume_position: (progress && progress.position) || 0.0
      })

    {:noreply, socket}
  end

  defp get_viewer_progress(_org, nil, _video), do: nil

  defp get_viewer_progress(org, viewer, video) do
    case Engagement.get_progress(org, viewer, video) do
      %{position: _} = progress -> progress
      _ -> nil
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
      Content.get_video!(socket.assigns.organization, video_id)
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
    %{results: queue_items} = Engagement.list_queue(org, viewer, per_page: 100)

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

  defp clamp_position(pos, duration)
       when is_number(pos) and is_number(duration) and duration > 0.0 do
    min(pos / 1, duration)
  end

  defp clamp_position(pos, _duration) when is_number(pos), do: pos / 1
  defp clamp_position(_pos, _duration), do: 0.0

  defp timed(fun) do
    started_at = System.monotonic_time()
    result = fun.()

    duration_ms =
      System.convert_time_unit(System.monotonic_time() - started_at, :native, :millisecond)

    {duration_ms, result}
  end
end
