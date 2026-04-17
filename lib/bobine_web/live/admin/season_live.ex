defmodule BobineWeb.Admin.SeasonLive do
  @moduledoc """
  Season detail page. Lists episodes in the season and supports two ways
  to add episodes:

    1. Upload new videos directly to Mux. Each successful upload is
       immediately attached to this season as the next episode.
    2. Pick from existing org videos that are not already episodes
       anywhere in this org.

  Episodes can be removed (the underlying video is preserved) and the
  cached `episode_count` on the season is kept in sync by the context.

  Hooks: MuxUploader (direct upload to Mux)
  Route: /admin/series/:series_id/seasons/:season_id
  """

  use BobineWeb, :live_view

  alias Bobine.Accounts
  alias Bobine.Content
  alias Bobine.Content.Episode
  alias Bobine.Events
  alias Bobine.Repo
  alias Bobine.Workers.MuxAssetCleanup

  import Ecto.Query, warn: false

  require Logger

  @impl true
  def mount(%{"series_id" => series_id, "season_id" => season_id}, _session, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    with {:ok, series} <- Content.get_series(org, series_id),
         {:ok, season} <- Content.get_season(org, season_id),
         true <- season.series_id == series.id do
      if connected?(socket) do
        Events.subscribe(org.id)
      end

      can_manage = Accounts.can_manage_content?(scope)

      {:ok,
       socket
       |> assign(:page_title, "#{series.title} — #{season.title}")
       |> assign(:can_manage, can_manage)
       |> assign(:series, series)
       |> assign(:season, season)
       |> assign(:show_upload_modal, false)
       |> assign(:upload_files, [])
       |> assign(:uploading, false)
       |> assign(:upload_total, 0)
       |> assign(:upload_completed, 0)
       |> assign(:upload_percent, 0)
       |> assign(:pending_episode_video_ids, [])
       |> assign(:show_picker, false)
       |> assign(:picker_videos, [])
       |> assign(:selected_video_ids, MapSet.new())
       |> load_episodes()}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/admin/series")}
    end
  end

  ## -----------------------------------------------------------------------
  ## Episode removal
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("remove_episode", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    season = socket.assigns.season

    with {:ok, video} <- Content.get_video(org, video_id),
         :ok <- Content.remove_episode(scope, season, video) do
      {:noreply,
       socket
       |> put_flash(:info, "Episode removed.")
       |> reload_season()
       |> load_episodes()}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Episode not found.")}
    end
  end

  ## -----------------------------------------------------------------------
  ## Existing-video picker
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("open_picker", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_picker, true)
     |> assign(:selected_video_ids, MapSet.new())
     |> load_picker_videos()}
  end

  @impl true
  def handle_event("close_picker", _params, socket) do
    {:noreply,
     assign(socket,
       show_picker: false,
       picker_videos: [],
       selected_video_ids: MapSet.new()
     )}
  end

  @impl true
  def handle_event("toggle_picker_video", %{"video-id" => video_id}, socket) do
    selected = socket.assigns.selected_video_ids

    selected =
      if MapSet.member?(selected, video_id) do
        MapSet.delete(selected, video_id)
      else
        MapSet.put(selected, video_id)
      end

    {:noreply, assign(socket, selected_video_ids: selected)}
  end

  @impl true
  def handle_event("add_selected_episodes", _params, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    season = socket.assigns.season

    selected_ids = MapSet.to_list(socket.assigns.selected_video_ids)

    Enum.each(selected_ids, fn video_id ->
      with {:ok, video} <- Content.get_video(org, video_id) do
        Content.add_episode(scope, season, video)
      end
    end)

    {:noreply,
     socket
     |> assign(show_picker: false, picker_videos: [], selected_video_ids: MapSet.new())
     |> put_flash(:info, "Added #{length(selected_ids)} episode(s).")
     |> reload_season()
     |> load_episodes()}
  end

  ## -----------------------------------------------------------------------
  ## Upload flow (mirrors ContentLive but auto-attaches each video as an episode)
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("open_upload", _params, socket) do
    {:noreply,
     assign(socket,
       show_upload_modal: true,
       upload_files: [],
       uploading: false,
       upload_total: 0,
       upload_completed: 0,
       upload_percent: 0,
       pending_episode_video_ids: []
     )}
  end

  @impl true
  def handle_event("close_upload", _params, socket) do
    if socket.assigns.uploading do
      {:noreply, socket}
    else
      {:noreply, assign(socket, show_upload_modal: false, upload_files: [])}
    end
  end

  @impl true
  def handle_event("files_selected", %{"files" => files}, socket) do
    upload_files =
      Enum.map(files, fn %{"client_id" => cid, "name" => name} ->
        title = name |> Path.rootname() |> String.replace(~r/[_\-\.]+/, " ") |> String.trim()
        %{client_id: cid, name: name, title: title}
      end)

    {:noreply, assign(socket, :upload_files, upload_files)}
  end

  @impl true
  def handle_event("submit_upload", params, socket) do
    titles = params["titles"] || %{}
    scope = socket.assigns.current_scope
    upload_files = socket.assigns.upload_files

    case build_upload_queue(scope, upload_files, titles, socket.assigns.current_origin) do
      {:ok, []} ->
        {:noreply, put_flash(socket, :error, "No files to upload.")}

      {:ok, queue} ->
        # Each video is attached to the season immediately, so when the upload
        # finishes the episode already exists. Mux processes the bytes async.
        attach_videos_as_episodes(scope, socket.assigns.season, queue)

        pending_ids = Enum.map(queue, & &1.video_id)

        {:noreply,
         socket
         |> assign(
           uploading: true,
           upload_total: length(queue),
           upload_completed: 0,
           upload_percent: 0,
           pending_episode_video_ids: pending_ids
         )
         |> push_event("start_multi_upload", %{queue: queue})
         |> reload_season()
         |> load_episodes()}

      {:error, :mux_error, reason} ->
        {:noreply, put_flash(socket, :error, mux_upload_error_message(reason))}

      {:error, :validation_failed, title} ->
        {:noreply, put_flash(socket, :error, "Invalid title for \"#{title}\".")}
    end
  end

  @impl true
  def handle_event("upload_progress", %{"video_id" => _id, "percent" => pct}, socket) do
    {:noreply, assign(socket, :upload_percent, pct)}
  end

  @impl true
  def handle_event("upload_complete", %{"video_id" => _id}, socket) do
    completed = socket.assigns.upload_completed + 1
    total = socket.assigns.upload_total

    if completed >= total do
      {:noreply,
       socket
       |> assign(
         show_upload_modal: false,
         uploading: false,
         upload_files: [],
         upload_total: 0,
         upload_completed: 0,
         upload_percent: 0,
         pending_episode_video_ids: []
       )
       |> put_flash(:info, "Upload complete. Mux is processing the video(s).")
       |> reload_season()
       |> load_episodes()}
    else
      {:noreply, assign(socket, upload_completed: completed, upload_percent: 0)}
    end
  end

  @impl true
  def handle_event("upload_error", %{"video_id" => video_id, "error" => error}, socket) do
    # Roll back the episode for this video so a failed upload does not leave
    # an orphaned episode pointing at a video that will never become ready.
    rollback_failed_episode(socket, video_id)

    completed = socket.assigns.upload_completed + 1
    total = socket.assigns.upload_total

    if completed >= total do
      {:noreply,
       socket
       |> assign(
         show_upload_modal: false,
         uploading: false,
         upload_files: [],
         upload_total: 0,
         upload_completed: 0,
         upload_percent: 0,
         pending_episode_video_ids: []
       )
       |> put_flash(:error, "Upload failed: #{error}")
       |> reload_season()
       |> load_episodes()}
    else
      {:noreply,
       socket
       |> assign(upload_completed: completed, upload_percent: 0)
       |> put_flash(:error, "One upload failed: #{error}")}
    end
  end

  ## -----------------------------------------------------------------------
  ## Real-time updates
  ## -----------------------------------------------------------------------

  @impl true
  def handle_info({:bobine_event, _event, _scope}, socket) do
    {:noreply, socket |> reload_season() |> load_episodes()}
  end

  ## -----------------------------------------------------------------------
  ## Render
  ## -----------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <BobineWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <%!-- Header / breadcrumbs --%>
      <div class="flex items-center justify-between pb-4">
        <div class="flex items-center gap-3">
          <.link
            navigate={~p"/admin/series"}
            class="btn btn-ghost btn-sm"
            data-test="back-to-series"
          >
            ← Series
          </.link>
          <div>
            <p class="text-xs text-base-content/60 uppercase tracking-wide">
              {@series.title}
            </p>
            <div data-test="season-page-title">
              <.header>{@season.title}</.header>
            </div>
          </div>
        </div>
        <div class="flex gap-2">
          <.link
            navigate={~p"/admin/analytics/series/#{@series.id}/seasons/#{@season.id}"}
            class="btn btn-outline btn-sm"
            data-test="view-season-analytics"
          >
            Analytics
          </.link>
          <button
            :if={@can_manage}
            phx-click="open_picker"
            class="btn btn-outline btn-sm"
            data-test="add-existing-btn"
          >
            Add Existing Video
          </button>
          <button
            :if={@can_manage}
            phx-click="open_upload"
            class="btn btn-primary btn-sm"
            data-test="upload-episode-btn"
          >
            Upload Episode
          </button>
        </div>
      </div>

      <p :if={@season.description} class="text-base-content/70 mb-4">
        {@season.description}
      </p>

      <%!-- Episode list --%>
      <div
        :if={@episodes == []}
        class="py-12 text-center text-base-content/60"
        data-test="episodes-empty"
      >
        <p class="text-lg">No episodes yet.</p>
        <p class="mt-2">Upload a video or pick from existing videos to get started.</p>
      </div>

      <div :if={@episodes != []} class="overflow-x-auto" data-test="episodes-list">
        <table class="table w-full">
          <thead>
            <tr>
              <th>#</th>
              <th>Episode</th>
              <th>Status</th>
              <th>Duration</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={ep <- @episodes} data-test={"episode-row-#{ep.id}"}>
              <td class="font-mono">{ep.episode_number}</td>
              <td class="flex items-center gap-3">
                <div class="w-24 h-14 rounded bg-base-300 overflow-hidden flex-shrink-0">
                  <img
                    :if={ep.video && ep.video.mux_playback_id}
                    src={"https://image.mux.com/#{ep.video.mux_playback_id}/thumbnail.webp?width=192&height=108"}
                    alt={ep.video.title}
                    class="w-full h-full object-cover"
                  />
                </div>
                <div>
                  <div class="font-medium">{ep.title || (ep.video && ep.video.title)}</div>
                  <div class="text-xs text-base-content/60 font-mono">
                    {ep.video && ep.video.slug}
                  </div>
                </div>
              </td>
              <td data-test={"episode-status-#{ep.id}"}>
                <.status_badge status={ep.video && ep.video.mux_status} />
              </td>
              <td class="text-sm text-base-content/70">
                {format_duration(ep.video && ep.video.duration)}
              </td>
              <td :if={@can_manage}>
                <button
                  phx-click="remove_episode"
                  phx-value-video-id={ep.video_id}
                  data-confirm="Remove this episode? The video will not be deleted."
                  class="btn btn-xs btn-outline btn-error"
                  data-test={"remove-episode-#{ep.id}"}
                >
                  Remove
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Persistent MuxUploader hook (must survive modal re-render) --%>
      <div id="season-mux-uploader" phx-hook="MuxUploader" phx-update="ignore"></div>

      <.upload_modal
        :if={@show_upload_modal}
        upload_files={@upload_files}
        uploading={@uploading}
        upload_total={@upload_total}
        upload_completed={@upload_completed}
        upload_percent={@upload_percent}
      />

      <.video_picker
        :if={@show_picker}
        videos={@picker_videos}
        selected_video_ids={@selected_video_ids}
      />
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  ## -----------------------------------------------------------------------
  ## Inline components
  ## -----------------------------------------------------------------------

  defp upload_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      data-test="episode-upload-modal"
    >
      <div class="bg-base-100 rounded-lg p-6 w-full max-w-lg shadow-xl max-h-[80vh] overflow-y-auto">
        <h3 class="text-lg font-semibold mb-4">Upload Episode</h3>

        <div :if={@uploading} class="mb-4" data-test="upload-progress-section">
          <p class="text-sm text-base-content/70 mb-2">
            Uploading {@upload_completed + 1} of {@upload_total}… {@upload_percent}%
          </p>
          <progress
            class="progress progress-primary w-full"
            value={@upload_percent}
            max="100"
            data-test="upload-progress"
          >
          </progress>
        </div>

        <div :if={!@uploading && @upload_files == []} data-test="upload-file-picker">
          <div class="mb-4">
            <label class="label" for="episode-upload-file">Select video files</label>
            <input
              type="file"
              id="episode-upload-file"
              name="video_file"
              accept="video/*"
              multiple
              class="file-input file-input-bordered w-full"
              data-test="upload-file"
            />
          </div>
          <div class="flex justify-end">
            <button type="button" phx-click="close_upload" class="btn btn-ghost">
              Cancel
            </button>
          </div>
        </div>

        <form
          :if={!@uploading && @upload_files != []}
          phx-submit="submit_upload"
          action="#"
          data-test="upload-form"
        >
          <p class="text-sm text-base-content/60 mb-3">
            {length(@upload_files)} file(s) selected. Each file becomes one episode.
          </p>

          <div class="space-y-3 mb-4">
            <div
              :for={file <- @upload_files}
              class="flex items-center gap-3"
              data-test={"upload-file-row-#{file.client_id}"}
            >
              <div class="text-xs text-base-content/50 w-32 truncate flex-shrink-0" title={file.name}>
                {file.name}
              </div>
              <input
                type="text"
                name={"titles[#{file.client_id}]"}
                value={file.title}
                class="input input-bordered input-sm flex-1"
                placeholder="Episode title"
                data-test={"upload-title-#{file.client_id}"}
              />
            </div>
          </div>

          <div class="flex justify-end gap-2">
            <button type="button" phx-click="close_upload" class="btn btn-ghost">Cancel</button>
            <button type="submit" class="btn btn-primary" data-test="upload-submit">
              Upload {length(@upload_files)} Episode{if length(@upload_files) > 1, do: "s", else: ""}
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp video_picker(assigns) do
    assigns = assign(assigns, :selected_count, MapSet.size(assigns.selected_video_ids))

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div
        class="bg-base-100 rounded-lg p-6 w-full max-w-lg shadow-xl max-h-[80vh] flex flex-col"
        data-test="episode-video-picker"
      >
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold">Add Existing Videos</h3>
          <button phx-click="close_picker" class="btn btn-ghost btn-sm" aria-label="Close">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div :if={@videos == []} class="py-8 text-center text-base-content/60">
          <p>No unassigned videos available.</p>
          <p class="mt-2 text-sm">All your videos are already episodes in some season.</p>
        </div>

        <div :if={@videos != []} class="overflow-y-auto flex-1 space-y-2">
          <label
            :for={video <- @videos}
            class="flex items-center gap-3 p-3 bg-base-200 rounded-lg cursor-pointer hover:bg-base-300"
            data-test={"picker-video-#{video.id}"}
          >
            <input
              type="checkbox"
              class="checkbox"
              checked={MapSet.member?(@selected_video_ids, video.id)}
              phx-click="toggle_picker_video"
              phx-value-video-id={video.id}
              data-test={"picker-video-checkbox-#{video.id}"}
            />
            <div class="w-20 h-12 rounded bg-base-300 overflow-hidden flex-shrink-0">
              <img
                :if={video.mux_playback_id}
                src={"https://image.mux.com/#{video.mux_playback_id}/thumbnail.webp?width=160&height=96"}
                alt={video.title}
                class="w-full h-full object-cover"
              />
            </div>
            <div class="flex-1 min-w-0">
              <div class="font-medium truncate">{video.title}</div>
              <div class="text-xs text-base-content/60">
                {format_duration(video.duration)}
              </div>
            </div>
          </label>
        </div>

        <div class="flex justify-between items-center mt-4 pt-4 border-t border-base-300">
          <span class="text-sm text-base-content/60">
            {@selected_count} selected
          </span>
          <div class="flex gap-2">
            <button phx-click="close_picker" class="btn btn-ghost btn-sm">Cancel</button>
            <button
              phx-click="add_selected_episodes"
              disabled={@selected_count == 0}
              class="btn btn-primary btn-sm"
              data-test="add-selected-episodes-btn"
            >
              Add Selected
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    {label, class} =
      case assigns.status do
        "ready" -> {"Ready", "badge-success"}
        "preparing" -> {"Processing", "badge-warning"}
        "waiting" -> {"Waiting", "badge-ghost"}
        "errored" -> {"Errored", "badge-error"}
        _ -> {"Unknown", "badge-ghost"}
      end

    assigns = assign(assigns, label: label, class: class)

    ~H"""
    <span class={"badge badge-sm #{@class}"}>{@label}</span>
    """
  end

  defp format_duration(nil), do: "—"

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

  defp format_duration(_), do: "—"

  ## -----------------------------------------------------------------------
  ## Private helpers
  ## -----------------------------------------------------------------------

  defp load_episodes(socket) do
    org = socket.assigns.organization
    season = socket.assigns.season
    episodes = Content.list_episodes(org, season)
    assign(socket, :episodes, episodes)
  end

  defp reload_season(socket) do
    org = socket.assigns.organization

    case Content.get_season(org, socket.assigns.season.id) do
      {:ok, season} -> assign(socket, :season, season)
      _ -> socket
    end
  end

  defp load_picker_videos(socket) do
    org = socket.assigns.organization
    %{results: all_videos} = Content.list_videos(org, per_page: 100)

    assigned_ids = assigned_video_ids(org)
    available = Enum.reject(all_videos, &MapSet.member?(assigned_ids, &1.id))

    assign(socket, :picker_videos, available)
  end

  # Returns the set of video IDs that are already episodes anywhere in the org.
  defp assigned_video_ids(%{id: org_id}) do
    Episode
    |> where(organization_id: ^org_id)
    |> select([e], e.video_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp build_upload_queue(scope, upload_files, titles, current_origin) do
    Enum.reduce_while(upload_files, {:ok, []}, fn file, {:ok, acc} ->
      title = String.trim(Map.get(titles, file.client_id, file.title))
      title = if title == "", do: file.title, else: title

      case Content.create_upload_url(scope, %{title: title, description: ""},
             current_origin: current_origin
           ) do
        {:ok, %{video: video, upload_url: url}} ->
          entry = %{
            client_id: file.client_id,
            video_id: video.id,
            upload_url: url,
            title: title
          }

          {:cont, {:ok, acc ++ [entry]}}

        {:error, :mux_error, reason} ->
          Logger.error("Season upload initiation failed",
            organization_id: scope.organization.id,
            user_id: scope.user.id,
            title: title,
            reason: inspect(reason)
          )

          {:halt, {:error, :mux_error, reason}}

        {:error, :validation, _changeset} ->
          {:halt, {:error, :validation_failed, title}}
      end
    end)
  end

  defp attach_videos_as_episodes(scope, season, queue) do
    Enum.each(queue, fn %{video_id: video_id} ->
      with {:ok, video} <- Content.get_video(scope.organization, video_id) do
        Content.add_episode(scope, season, video)
      end
    end)
  end

  defp rollback_failed_episode(socket, video_id) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    season = socket.assigns.season

    with {:ok, video} <- Content.get_video(org, video_id) do
      _ = Content.remove_episode(scope, season, video)
      _ = Content.delete_video(video)

      if video.mux_asset_id do
        %{"mux_asset_id" => video.mux_asset_id, "organization_id" => org.id}
        |> Bobine.Otel.put_trace_context()
        |> MuxAssetCleanup.new()
        |> Oban.insert()
      end
    end
  end

  defp mux_upload_error_message(%{type: type, messages: messages}) do
    base =
      "Mux could not start this upload. Your Mux account may have reached an asset or upload limit."

    details =
      [type | List.wrap(messages)]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("; ")

    if details == "", do: base, else: "#{base} Details: #{details}"
  end

  defp mux_upload_error_message(reason) when is_binary(reason) do
    "Mux could not start this upload. #{reason}"
  end

  defp mux_upload_error_message(_reason) do
    "Mux could not start this upload."
  end
end
