defmodule BobineWeb.Admin.ContentLive.Components do
  @moduledoc """
  Template components for the content management LiveView.

  Extracted from `ContentLive` to keep the LiveView module focused on
  event handling and state management.
  """

  use BobineWeb, :html

  @doc """
  Renders the video list table with search, empty state, and upload modal.
  """
  def video_list(assigns) do
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

  @doc """
  Renders the video detail view with edit form and tag management.
  """
  def video_detail(assigns) do
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

  @doc """
  Renders a colored status badge for a Mux video status.
  """
  def status_badge(%{status: "ready"} = assigns) do
    ~H"""
    <span class="badge badge-success badge-sm">Ready</span>
    """
  end

  def status_badge(%{status: "preparing"} = assigns) do
    ~H"""
    <span class="badge badge-warning badge-sm">Processing</span>
    """
  end

  def status_badge(%{status: "waiting"} = assigns) do
    ~H"""
    <span class="badge badge-info badge-sm">Uploading</span>
    """
  end

  def status_badge(%{status: "errored"} = assigns) do
    ~H"""
    <span class="badge badge-error badge-sm">Error</span>
    """
  end

  def status_badge(assigns) do
    ~H"""
    <span class="badge badge-ghost badge-sm">{@status}</span>
    """
  end

  @doc """
  Formats a duration in seconds to a `M:SS` string.

  Returns a dash when the duration is nil.

      iex> BobineWeb.Admin.ContentLive.Components.format_duration(nil)
      "—"

      iex> BobineWeb.Admin.ContentLive.Components.format_duration(125.0)
      "2:05"

      iex> BobineWeb.Admin.ContentLive.Components.format_duration(60.0)
      "1:00"
  """
  def format_duration(nil), do: "—"

  def format_duration(seconds) when is_float(seconds) do
    total = round(seconds)
    mins = div(total, 60)
    secs = rem(total, 60)
    "#{mins}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  @doc """
  Returns tags from `all_tags` that are not already in `video_tags`.

      iex> all = [%{id: 1, name: "A"}, %{id: 2, name: "B"}]
      iex> assigned = [%{id: 1, name: "A"}]
      iex> BobineWeb.Admin.ContentLive.Components.available_tags(all, assigned)
      [%{id: 2, name: "B"}]
  """
  def available_tags(all_tags, video_tags) do
    assigned_ids = MapSet.new(video_tags, & &1.id)
    Enum.reject(all_tags, fn tag -> MapSet.member?(assigned_ids, tag.id) end)
  end
end
