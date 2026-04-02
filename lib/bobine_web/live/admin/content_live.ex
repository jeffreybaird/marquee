defmodule BobineWeb.Admin.ContentLive do
  use BobineWeb, :live_view

  alias Bobine.Content
  alias Bobine.Events

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Events.subscribe(org.id)
      Events.subscribe_global()
    end

    can_manage = can_manage_content?(scope)

    {:ok,
     socket
     |> assign(:page_title, "Content")
     |> assign(:search, "")
     |> assign(:show_upload_modal, false)
     |> assign(:upload_files, [])
     |> assign(:uploading, false)
     |> assign(:upload_total, 0)
     |> assign(:upload_completed, 0)
     |> assign(:upload_percent, 0)
     |> assign(:can_manage, can_manage)
     |> assign(:viewing_video, nil)
     |> assign(:video_tags, [])
     |> assign(:all_tags, [])
     |> assign(:editing_video, false)
     |> assign(:show_tag_picker, false)
     |> load_videos()}
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    {:noreply, socket |> assign(:search, term) |> load_videos()}
  end

  @impl true
  def handle_event("open_upload", _params, socket) do
    {:noreply,
     assign(socket,
       show_upload_modal: true,
       upload_files: [],
       uploading: false,
       upload_total: 0,
       upload_completed: 0,
       upload_percent: 0
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

    # Build the upload queue: create a Mux upload URL for each file
    upload_queue =
      Enum.reduce_while(upload_files, {:ok, []}, fn file, {:ok, acc} ->
        title = String.trim(Map.get(titles, file.client_id, file.title))
        title = if title == "", do: file.title, else: title

        case Content.create_upload_url(scope, %{title: title, description: ""},
               current_origin: socket.assigns.current_origin
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
            Logger.error("Admin upload initiation failed",
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

    case upload_queue do
      {:ok, queue} when queue != [] ->
        {:noreply,
         socket
         |> assign(
           uploading: true,
           upload_total: length(queue),
           upload_completed: 0,
           upload_percent: 0
         )
         |> push_event("start_multi_upload", %{queue: queue})
         |> load_videos()}

      {:ok, []} ->
        {:noreply, put_flash(socket, :error, "No files to upload.")}

      {:error, :mux_error, reason} ->
        {:noreply, put_flash(socket, :error, mux_upload_error_message(reason))}

      {:error, :validation_failed, title} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Invalid title for \"#{title}\". Please provide a valid title."
         )}
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
         upload_percent: 0
       )
       |> put_flash(:info, upload_complete_message(total))
       |> load_videos()}
    else
      {:noreply,
       socket
       |> assign(upload_completed: completed, upload_percent: 0)
       |> load_videos()}
    end
  end

  @impl true
  def handle_event("upload_error", %{"video_id" => _id, "error" => error}, socket) do
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
         upload_percent: 0
       )
       |> put_flash(:error, "Upload failed: #{error}")
       |> load_videos()}
    else
      {:noreply,
       socket
       |> assign(upload_completed: completed, upload_percent: 0)
       |> put_flash(:error, "Upload failed: #{error}")
       |> load_videos()}
    end
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

        {:noreply,
         socket
         |> assign(:viewing_video, nil)
         |> put_flash(:info, "Video deleted.")
         |> load_videos()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Video not found.")}
    end
  end

  # --- Video detail view ---

  @impl true
  def handle_event("view_video", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Content.get_video(org, id) do
      {:ok, video} ->
        tags = Content.list_video_tags(org, video)

        {:noreply,
         socket
         |> assign(:viewing_video, video)
         |> assign(:video_tags, tags)
         |> assign(:editing_video, false)
         |> assign(:show_tag_picker, false)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Video not found.")}
    end
  end

  @impl true
  def handle_event("back_to_list", _params, socket) do
    {:noreply,
     socket
     |> assign(:viewing_video, nil)
     |> assign(:video_tags, [])
     |> assign(:editing_video, false)
     |> assign(:show_tag_picker, false)}
  end

  @impl true
  def handle_event("edit_video", _params, socket) do
    {:noreply, assign(socket, :editing_video, true)}
  end

  @impl true
  def handle_event("save_video", %{"video" => params}, socket) do
    video = socket.assigns.viewing_video

    case Content.update_video(video, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:viewing_video, updated)
         |> assign(:editing_video, false)
         |> put_flash(:info, "Video updated.")
         |> load_videos()}

      {:error, :validation, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update video.")}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_video, false)}
  end

  # --- Tag management ---

  @impl true
  def handle_event("open_tag_picker", _params, socket) do
    org = socket.assigns.organization
    %{results: all_tags} = Content.list_tags(org)
    {:noreply, assign(socket, show_tag_picker: true, all_tags: all_tags)}
  end

  @impl true
  def handle_event("close_tag_picker", _params, socket) do
    {:noreply, assign(socket, :show_tag_picker, false)}
  end

  @impl true
  def handle_event("add_tag", %{"tag-id" => tag_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    video = socket.assigns.viewing_video

    case Content.get_tag(org, tag_id) do
      {:ok, tag} ->
        case Content.tag_video(scope, video, tag) do
          {:ok, _} ->
            tags = Content.list_video_tags(org, video)

            {:noreply,
             socket
             |> assign(:video_tags, tags)
             |> assign(:show_tag_picker, false)}

          {:error, :already_exists} ->
            {:noreply, put_flash(socket, :error, "Tag already applied.")}

          {:error, _, _} ->
            {:noreply, put_flash(socket, :error, "Failed to add tag.")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Tag not found.")}
    end
  end

  @impl true
  def handle_event("remove_tag", %{"tag-id" => tag_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    video = socket.assigns.viewing_video

    case Content.get_tag(org, tag_id) do
      {:ok, tag} ->
        :ok = Content.untag_video(scope, video, tag)
        tags = Content.list_video_tags(org, video)
        {:noreply, assign(socket, :video_tags, tags)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Tag not found.")}
    end
  end

  defp upload_complete_message(1), do: "Upload complete. Processing video..."

  defp upload_complete_message(count),
    do: "All #{count} uploads complete. Processing videos..."

  defp mux_upload_error_message(%{type: type, messages: messages}) do
    base =
      "Mux could not start this upload. Your Mux account may have reached an asset or upload limit."

    details =
      [type | List.wrap(messages)]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("; ")

    if details == "" do
      base
    else
      "#{base} Details: #{details}"
    end
  end

  defp mux_upload_error_message(reason) when is_binary(reason) do
    "Mux could not start this upload. #{reason}"
  end

  defp mux_upload_error_message(_reason) do
    "Mux could not start this upload. Your Mux account may have reached an asset or upload limit."
  end

  # --- PubSub handlers ---

  @impl true
  def handle_info({:bobine_event, {:video_ready, video}, _scope}, socket) do
    socket = update_video_in_list(socket, video)

    socket =
      if socket.assigns.viewing_video && socket.assigns.viewing_video.id == video.id do
        assign(socket, :viewing_video, video)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:bobine_event, {:video_errored, video}, _scope}, socket) do
    socket = update_video_in_list(socket, video)

    socket =
      if socket.assigns.viewing_video && socket.assigns.viewing_video.id == video.id do
        assign(socket, :viewing_video, video)
      else
        socket
      end

    {:noreply, socket}
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
      flash={@flash}
    >
      <%!-- Persistent MuxUploader hook — lives outside the modal so it survives modal close --%>
      <div id="mux-uploader" phx-hook="MuxUploader" class="hidden"></div>

      <%= if @viewing_video do %>
        <.video_detail
          video={@viewing_video}
          video_tags={@video_tags}
          all_tags={@all_tags}
          editing={@editing_video}
          show_tag_picker={@show_tag_picker}
          can_manage={@can_manage}
        />
      <% else %>
        <.video_list
          videos={@videos}
          search={@search}
          can_manage={@can_manage}
          show_upload_modal={@show_upload_modal}
          upload_files={@upload_files}
          uploading={@uploading}
          upload_total={@upload_total}
          upload_completed={@upload_completed}
          upload_percent={@upload_percent}
        />
      <% end %>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp video_list(assigns) do
    ~H"""
    <div class="flex items-center justify-between pb-4">
      <.header>Content</.header>
      <button
        :if={@can_manage}
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
      <table class="table w-full" data-test="video-list">
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
                <button
                  phx-click="view_video"
                  phx-value-id={video.id}
                  class="font-medium hover:text-primary hover:underline text-left"
                  data-test={"view-video-#{video.id}"}
                >
                  {video.title}
                </button>
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
            <td :if={@can_manage}>
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
      <div class="bg-base-100 rounded-lg p-6 w-full max-w-lg shadow-xl max-h-[80vh] overflow-y-auto">
        <h3 class="text-lg font-semibold mb-4">Upload Videos</h3>

        <%!-- Upload progress --%>
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

        <%!-- Step 1: File selection (no files chosen yet, not uploading) --%>
        <div :if={!@uploading && @upload_files == []} data-test="upload-file-picker">
          <div class="mb-4">
            <label class="label" for="upload-file">Select video files</label>
            <input
              type="file"
              id="upload-file"
              name="video_file"
              accept="video/*"
              multiple
              class="file-input file-input-bordered w-full"
              data-test="upload-file"
            />
          </div>
          <div class="flex justify-end">
            <button
              type="button"
              phx-click="close_upload"
              class="btn btn-ghost"
            >
              Cancel
            </button>
          </div>
        </div>

        <%!-- Step 2: Assign titles to each file --%>
        <form
          :if={!@uploading && @upload_files != []}
          phx-submit="submit_upload"
          action="#"
          data-test="upload-form"
        >
          <p class="text-sm text-base-content/60 mb-3">
            {length(@upload_files)} file(s) selected. Assign a title to each video:
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
                placeholder="Video title"
                data-test={"upload-title-#{file.client_id}"}
              />
            </div>
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
              Upload {length(@upload_files)} Video{if length(@upload_files) > 1, do: "s", else: ""}
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp video_detail(assigns) do
    ~H"""
    <div data-test="video-detail">
      <div class="flex items-center gap-2 mb-4">
        <button
          phx-click="back_to_list"
          class="btn btn-ghost btn-sm"
          data-test="back-to-list-btn"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Back
        </button>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <%!-- Video info panel --%>
        <div class="lg:col-span-2 space-y-4">
          <%!-- Thumbnail --%>
          <div
            :if={@video.mux_playback_id}
            class="w-full aspect-video rounded-lg bg-base-300 overflow-hidden"
          >
            <img
              src={"https://image.mux.com/#{@video.mux_playback_id}/thumbnail.webp?width=640&height=360"}
              alt={@video.title}
              class="w-full h-full object-cover"
            />
          </div>

          <%!-- Edit form --%>
          <div :if={@editing} data-test="video-edit-form">
            <form phx-submit="save_video" class="space-y-4">
              <div>
                <label class="label">Title</label>
                <input
                  type="text"
                  name="video[title]"
                  value={@video.title}
                  class="input input-bordered w-full"
                  data-test="video-title-input"
                />
              </div>
              <div>
                <label class="label">Description</label>
                <textarea
                  name="video[description]"
                  class="textarea textarea-bordered w-full"
                  rows="4"
                  data-test="video-description-input"
                >{@video.description}</textarea>
              </div>
              <div class="flex gap-2">
                <button type="submit" class="btn btn-primary btn-sm" data-test="save-video-btn">
                  Save
                </button>
                <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">
                  Cancel
                </button>
              </div>
            </form>
          </div>

          <%!-- Read-only info --%>
          <div :if={!@editing} class="space-y-2">
            <div class="flex items-center justify-between">
              <h2 class="text-xl font-semibold" data-test="video-title">{@video.title}</h2>
              <button
                :if={@can_manage}
                phx-click="edit_video"
                class="btn btn-outline btn-sm"
                data-test="edit-video-btn"
              >
                Edit
              </button>
            </div>
            <p class="text-base-content/70" data-test="video-description">
              {@video.description || "No description."}
            </p>
            <div class="flex gap-4 text-sm text-base-content/60">
              <span>Status: <.status_badge status={@video.mux_status} /></span>
              <span>Duration: {format_duration(@video.duration)}</span>
              <span>Uploaded: {Calendar.strftime(@video.inserted_at, "%b %d, %Y")}</span>
            </div>
          </div>
        </div>

        <%!-- Tags sidebar --%>
        <div class="space-y-4" data-test="video-tags-panel">
          <div class="flex items-center justify-between">
            <h3 class="font-semibold">Tags</h3>
            <button
              :if={@can_manage}
              phx-click="open_tag_picker"
              class="btn btn-outline btn-xs"
              data-test="add-tag-btn"
            >
              Add Tag
            </button>
          </div>

          <div
            :if={@video_tags == []}
            class="text-sm text-base-content/50"
            data-test="no-tags"
          >
            No tags assigned.
          </div>

          <div :if={@video_tags != []} class="flex flex-wrap gap-2" data-test="video-tags-list">
            <span
              :for={tag <- @video_tags}
              class="badge badge-lg gap-1"
              data-test={"video-tag-#{tag.id}"}
            >
              {tag.name}
              <button
                :if={@can_manage}
                phx-click="remove_tag"
                phx-value-tag-id={tag.id}
                class="btn btn-ghost btn-xs p-0"
                data-test={"remove-tag-#{tag.id}"}
              >
                <.icon name="hero-x-mark" class="size-3" />
              </button>
            </span>
          </div>

          <%!-- Tag picker modal --%>
          <div
            :if={@show_tag_picker}
            class="border border-base-300 rounded-lg p-3 space-y-2 bg-base-200"
            data-test="tag-picker"
          >
            <p class="text-sm font-medium">Select a tag:</p>
            <%= for tag <- available_tags(@all_tags, @video_tags) do %>
              <button
                phx-click="add_tag"
                phx-value-tag-id={tag.id}
                class="btn btn-sm btn-outline w-full justify-start"
                data-test={"pick-tag-#{tag.id}"}
              >
                {tag.name}
              </button>
            <% end %>
            <div
              :if={available_tags(@all_tags, @video_tags) == []}
              class="text-sm text-base-content/50"
            >
              All tags assigned. Create more in Tags.
            </div>
            <button
              phx-click="close_tag_picker"
              class="btn btn-ghost btn-xs mt-2"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    </div>
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

  defp available_tags(all_tags, video_tags) do
    assigned_ids = MapSet.new(video_tags, & &1.id)
    Enum.reject(all_tags, fn tag -> MapSet.member?(assigned_ids, tag.id) end)
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

  defp can_manage_content?(%{user: %{is_super_admin: true}}), do: true

  defp can_manage_content?(%{membership: %{role: role}}) when role in [:owner, :admin, :editor],
    do: true

  defp can_manage_content?(_), do: false
end
