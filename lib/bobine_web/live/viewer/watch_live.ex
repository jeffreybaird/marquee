# TODO: Convert to static page with LiveView island for the player
defmodule BobineWeb.Viewer.WatchLive do
  use BobineWeb, :live_view

  alias Bobine.Content
  alias Bobine.Engagement

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Content.get_video(org, id) do
      {:ok, %{mux_status: "ready"} = video} ->
        progress = if scope && scope.user, do: Engagement.get_progress(scope, video.id)
        resume_position = if progress, do: progress.position, else: 0.0

        if connected?(socket) do
          Bobine.Metrics.video_viewed(org.id, video.id)
        end

        {:ok,
         assign(socket,
           video: video,
           page_title: video.title,
           resume_position: resume_position
         )}

      {:ok, _video} ->
        {:ok, push_navigate(socket, to: ~p"/")}

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event("playback_started", %{"video_id" => _id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("playback_progress", %{"video_id" => video_id, "position" => pos}, socket) do
    scope = socket.assigns.current_scope

    if scope && scope.user do
      Engagement.update_progress(scope, video_id, pos)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("playback_paused", %{"video_id" => video_id, "position" => pos}, socket) do
    scope = socket.assigns.current_scope

    if scope && scope.user do
      Engagement.update_progress(scope, video_id, pos)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("playback_ended", %{"video_id" => _id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-5xl mx-auto">
        <div
          id="player-container"
          phx-hook="MuxPlayer"
          data-playback-id={@video.mux_playback_id}
          data-video-id={@video.id}
          data-resume-position={@resume_position}
          data-test="player-container"
        >
          <mux-player
            stream-type="on-demand"
            playback-id={@video.mux_playback_id}
            metadata-video-title={@video.title}
            class="w-full aspect-video rounded-lg"
            data-test="mux-player"
          >
          </mux-player>
        </div>

        <div class="mt-6">
          <h1 class="text-2xl font-bold" data-test="video-title">{@video.title}</h1>
          <p :if={@video.description} class="mt-2 text-base-content/70" data-test="video-description">
            {@video.description}
          </p>
        </div>

        <div class="mt-4 flex gap-2">
          <%!-- Placeholder for Feature 06: Watchlist + Favorites --%>
          <button class="btn btn-outline btn-sm" disabled>Add to Watchlist</button>
          <button class="btn btn-outline btn-sm" disabled>Favorite</button>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
