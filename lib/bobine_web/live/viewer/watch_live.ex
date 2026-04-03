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
          nil

        scope && scope.user ->
          Engagement.get_progress(scope, video.id)

        true ->
          nil
      end

    resume_position = if progress, do: progress.position, else: 0.0

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
       related_videos: related
     )}
  end

  defp handle_access_denied(socket, _video, viewer) do
    if is_nil(viewer) do
      {:ok, push_navigate(socket, to: ~p"/login")}
    else
      {:ok, push_navigate(socket, to: ~p"/subscribe")}
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
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path={~p"/watch/#{@video.id}"}
      theme={@theme}
      flash={@flash}
    >
      <div class="sv-watch-layout">
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

          <div class="sv-video-actions">
            <button class="sv-btn sv-btn-secondary" disabled aria-label="Add to watchlist">
              <.icon name="hero-bookmark" class="size-5 mr-2" aria-hidden="true" /> Watchlist
            </button>
            <button class="sv-btn sv-btn-secondary" disabled aria-label="Favorite">
              <.icon name="hero-heart" class="size-5 mr-2" aria-hidden="true" /> Favorite
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
