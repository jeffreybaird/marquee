defmodule BobineWeb.Admin.ContentLive do
  use BobineWeb, :live_view

  alias Bobine.Content
  alias Bobine.Events

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization

    if connected?(socket) do
      Events.subscribe(org.id)
    end

    {:ok,
     socket
     |> assign(:page_title, "Content")
     |> assign(:search, "")
     |> assign(:show_upload_modal, false)
     |> assign(:uploading, false)
     |> assign(:upload_percent, 0)
     |> load_videos()}
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    {:noreply, socket |> assign(:search, term) |> load_videos()}
  end

  @impl true
  def handle_event("open_upload", _params, socket) do
    {:noreply, assign(socket, show_upload_modal: true, uploading: false, upload_percent: 0)}
  end

  @impl true
  def handle_event("close_upload", _params, socket) do
    if socket.assigns.uploading do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :show_upload_modal, false)}
    end
  end

  @impl true
  def handle_event("submit_upload", %{"title" => title, "description" => desc}, socket) do
    scope = socket.assigns.current_scope

    case Content.create_upload_url(scope, %{title: title, description: desc}) do
      {:ok, %{video: video, upload_url: url}} ->
        {:noreply,
         socket
         |> assign(:uploading, true)
         |> assign(:upload_percent, 0)
         |> push_event("start_upload", %{upload_url: url, video_id: video.id})
         |> load_videos()}

      {:error, :mux_error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to initiate upload. Please try again.")}

      {:error, :validation, _changeset} ->
        {:noreply, put_flash(socket, :error, "Please provide a title for the video.")}
    end
  end

  @impl true
  def handle_event("upload_progress", %{"video_id" => _id, "percent" => pct}, socket) do
    {:noreply, assign(socket, :upload_percent, pct)}
  end

  @impl true
  def handle_event("upload_complete", %{"video_id" => _id}, socket) do
    {:noreply,
     socket
     |> assign(show_upload_modal: false, uploading: false, upload_percent: 0)
     |> put_flash(:info, "Upload complete. Processing video...")
     |> load_videos()}
  end

  @impl true
  def handle_event("upload_error", %{"video_id" => _id, "error" => error}, socket) do
    {:noreply,
     socket
     |> assign(uploading: false, upload_percent: 0)
     |> put_flash(:error, "Upload failed: #{error}")}
  end

  @impl true
  def handle_event("delete_video", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Content.get_video(org, id) do
      {:ok, video} ->
        {:ok, _} = Content.delete_video(video)

        if video.mux_asset_id do
          %{mux_asset_id: video.mux_asset_id, organization_id: org.id}
          |> Bobine.Workers.MuxAssetCleanup.new()
          |> Oban.insert()
        end

        {:noreply, socket |> put_flash(:info, "Video deleted.") |> load_videos()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Video not found.")}
    end
  end

  @impl true
  def handle_info({:bobine_event, {:video_ready, video}, _scope}, socket) do
    {:noreply, update_video_in_list(socket, video)}
  end

  @impl true
  def handle_info({:bobine_event, {:video_errored, video}, _scope}, socket) do
    {:noreply, update_video_in_list(socket, video)}
  end

  @impl true
  def handle_info({:bobine_event, {:video_upload_initiated, _video}, _scope}, socket) do
    {:noreply, load_videos(socket)}
  end

  @impl true
  def handle_info({:bobine_event, _event, _scope}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <BobineWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <%!-- Persistent MuxUploader hook — lives outside the modal so it survives modal close --%>
      <div id="mux-uploader" phx-hook="MuxUploader" class="hidden"></div>

      <div class="flex items-center justify-between pb-4">
        <.header>Content</.header>
        <button
          phx-click="open_upload"
          class="btn btn-primary"
          data-test="upload-btn"
        >
          Upload Video
        </button>
      </div>

      <div class="mb-4">
        <.input
          type="text"
          name="search"
          value={@search}
          placeholder="Search videos by title…"
          phx-change="search"
          phx-debounce="300"
          data-test="video-search"
        />
      </div>

      <div
        :if={@videos == []}
        class="py-12 text-center text-base-content/60"
        data-test="empty-state"
      >
        <p class="text-lg">No videos yet.</p>
        <p class="mt-2">Upload your first video to get started.</p>
      </div>

      <div :if={@videos != []} class="overflow-x-auto">
        <table class="table w-full">
          <thead>
            <tr>
              <th>Video</th>
              <th>Status</th>
              <th>Duration</th>
              <th>Uploaded</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={video <- @videos} data-test={"video-row-#{video.id}"}>
              <td class="flex items-center gap-3">
                <div class="w-24 h-14 rounded bg-base-300 overflow-hidden flex-shrink-0">
                  <img
                    :if={video.mux_playback_id}
                    src={"https://image.mux.com/#{video.mux_playback_id}/thumbnail.webp?width=192&height=108"}
                    alt={video.title}
                    class="w-full h-full object-cover"
                  />
                </div>
                <div>
                  <div class="font-medium">{video.title}</div>
                  <div class="text-xs text-base-content/60 font-mono">{video.slug}</div>
                </div>
              </td>
              <td data-test={"video-status-#{video.id}"}>
                <.status_badge status={video.mux_status} />
              </td>
              <td class="text-sm text-base-content/70">
                {format_duration(video.duration)}
              </td>
              <td class="text-sm text-base-content/60">
                {Calendar.strftime(video.inserted_at, "%b %d, %Y")}
              </td>
              <td>
                <button
                  phx-click="delete_video"
                  phx-value-id={video.id}
                  data-confirm="Are you sure you want to delete this video?"
                  class="btn btn-xs btn-outline btn-error"
                  data-test={"delete-video-#{video.id}"}
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Upload modal --%>
      <div
        :if={@show_upload_modal}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
        data-test="upload-modal"
      >
        <div class="bg-base-100 rounded-lg p-6 w-full max-w-md shadow-xl">
          <h3 class="text-lg font-semibold mb-4">Upload Video</h3>

          <%!-- Upload progress --%>
          <div :if={@uploading} class="mb-4">
            <p class="text-sm text-base-content/70 mb-2">Uploading... {@upload_percent}%</p>
            <progress
              class="progress progress-primary w-full"
              value={@upload_percent}
              max="100"
              data-test="upload-progress"
            >
            </progress>
          </div>

          <%!-- Upload form (hidden while uploading) --%>
          <form
            :if={!@uploading}
            phx-submit="submit_upload"
            action="#"
            data-test="upload-form"
          >
            <div class="mb-4">
              <label class="label" for="upload-title">Title</label>
              <input
                type="text"
                id="upload-title"
                name="title"
                required
                class="input input-bordered w-full"
                data-test="upload-title"
              />
            </div>
            <div class="mb-4">
              <label class="label" for="upload-desc">Description</label>
              <textarea
                id="upload-desc"
                name="description"
                class="textarea textarea-bordered w-full"
                rows="3"
                data-test="upload-description"
              >
              </textarea>
            </div>
            <div class="mb-4">
              <label class="label" for="upload-file">Video file</label>
              <input
                type="file"
                id="upload-file"
                name="video_file"
                accept="video/*"
                class="file-input file-input-bordered w-full"
                data-test="upload-file"
              />
            </div>
            <div class="flex justify-end gap-2">
              <button
                type="button"
                phx-click="close_upload"
                class="btn btn-ghost"
              >
                Cancel
              </button>
              <button type="submit" class="btn btn-primary" data-test="upload-submit">
                Upload
              </button>
            </div>
          </form>
        </div>
      </div>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp status_badge(%{status: "ready"} = assigns) do
    ~H"""
    <span class="badge badge-success badge-sm">Ready</span>
    """
  end

  defp status_badge(%{status: "preparing"} = assigns) do
    ~H"""
    <span class="badge badge-warning badge-sm">Processing</span>
    """
  end

  defp status_badge(%{status: "waiting"} = assigns) do
    ~H"""
    <span class="badge badge-info badge-sm">Uploading</span>
    """
  end

  defp status_badge(%{status: "errored"} = assigns) do
    ~H"""
    <span class="badge badge-error badge-sm">Error</span>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <span class="badge badge-ghost badge-sm">{@status}</span>
    """
  end

  defp format_duration(nil), do: "—"

  defp format_duration(seconds) when is_float(seconds) do
    total = round(seconds)
    mins = div(total, 60)
    secs = rem(total, 60)
    "#{mins}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp load_videos(socket) do
    org = socket.assigns.organization
    search = socket.assigns.search
    %{results: videos} = Content.list_videos(org, search: search)
    assign(socket, :videos, videos)
  end

  defp update_video_in_list(socket, updated_video) do
    videos =
      Enum.map(socket.assigns.videos, fn v ->
        if v.id == updated_video.id, do: updated_video, else: v
      end)

    assign(socket, :videos, videos)
  end
end
