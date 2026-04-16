defmodule BobineWeb.Admin.ContentLive.Components do
  @moduledoc """
  Template components for the content management LiveView.

  Extracted from `ContentLive` to keep the LiveView module focused on
  event handling and state management.

  All admin surfaces render through `BobineWeb.Components.AdminUI`
  primitives (`admin_panel`, `admin_sheet`, `admin_button`, `admin_empty`)
  so the admin-scoped token palette stays consistent. Viewer / daisyUI
  tokens (`base-*`, `btn-*`) must not appear here.
  """

  use BobineWeb, :html

  alias BobineWeb.Components.AdminUI

  @doc """
  Renders the video list table with search, empty state, and upload sheet.
  """
  def video_list(assigns) do
    ~H"""
    <AdminUI.admin_panel
      title="Content"
      subtitle="Manage videos, thumbnails, and tags across your catalog."
    >
      <:actions>
        <AdminUI.admin_button
          :if={@can_manage}
          phx-click="open_upload"
          size={:sm}
          data-test="upload-btn"
        >
          Upload Video
        </AdminUI.admin_button>
      </:actions>

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

      <AdminUI.admin_empty
        :if={@videos == []}
        title="No videos yet."
        description="Upload your first video to get started."
        data_test="empty-state"
      />

      <div :if={@videos != []} class="overflow-x-auto">
        <table
          class="w-full border-collapse font-body text-sm text-admin-fg"
          data-test="video-list"
        >
          <thead>
            <tr class="border-b border-admin-border text-left font-ui text-xs uppercase tracking-wide text-admin-muted">
              <th class="py-2 pr-4">Video</th>
              <th class="py-2 pr-4">Tags</th>
              <th class="py-2 pr-4">Status</th>
              <th class="py-2 pr-4">Duration</th>
              <th class="py-2 pr-4">Uploaded</th>
              <th class="py-2"></th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={video <- @videos}
              class="border-b border-admin-border"
              data-test={"video-row-#{video.id}"}
            >
              <td class="py-3 pr-4">
                <div class="flex items-center gap-3">
                  <div class="h-14 w-24 flex-shrink-0 overflow-hidden rounded bg-admin-card">
                    <img
                      :if={video.mux_playback_id}
                      src={"https://image.mux.com/#{video.mux_playback_id}/thumbnail.webp?width=192&height=108"}
                      alt={video.title}
                      class="h-full w-full object-cover"
                    />
                  </div>
                  <div>
                    <button
                      phx-click="view_video"
                      phx-value-id={video.id}
                      class="text-left font-display font-semibold text-admin-fg hover:text-admin-accent hover:underline"
                      data-test={"view-video-#{video.id}"}
                    >
                      {video.title}
                    </button>
                    <div class="font-mono text-xs text-admin-muted">{video.slug}</div>
                  </div>
                </div>
              </td>
              <td class="py-3 pr-4" data-test={"row-tags-#{video.id}"}>
                <.row_tags
                  video={video}
                  tags={Map.get(@videos_tags_map, video.id, [])}
                  can_manage={@can_manage}
                  picker_open={@row_tag_picker_video_id == video.id}
                  all_tags={@all_tags}
                  tag_search={@tag_search}
                />
              </td>
              <td class="py-3 pr-4" data-test={"video-status-#{video.id}"}>
                <.status_badge status={video.mux_status} />
              </td>
              <td class="py-3 pr-4 font-mono text-sm text-admin-muted">
                {format_duration(video.duration)}
              </td>
              <td class="py-3 pr-4 font-mono text-sm text-admin-muted">
                {Calendar.strftime(video.inserted_at, "%b %d, %Y")}
              </td>
              <td :if={@can_manage} class="py-3">
                <AdminUI.admin_button
                  variant={:danger}
                  size={:sm}
                  phx-click="delete_video"
                  phx-value-id={video.id}
                  data-confirm="Are you sure you want to delete this video?"
                  data-test={"delete-video-#{video.id}"}
                >
                  Delete
                </AdminUI.admin_button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </AdminUI.admin_panel>

    <AdminUI.admin_sheet
      id="upload-sheet"
      open={@show_upload_modal}
      title="Upload Videos"
      subtitle="Direct-to-Mux upload. Titles default from filename."
      on_close="close_upload"
      data_test="upload-modal"
    >
      <%!-- Upload progress --%>
      <div :if={@uploading} class="mb-4" data-test="upload-progress-section">
        <p class="mb-2 font-body text-sm text-admin-muted">
          Uploading <span class="font-mono">{@upload_completed + 1}</span>
          of <span class="font-mono">{@upload_total}</span>…
          <span class="font-mono">{@upload_percent}%</span>
        </p>
        <progress
          class="w-full rounded bg-admin-card [&::-webkit-progress-bar]:bg-admin-card [&::-webkit-progress-value]:bg-admin-accent [&::-moz-progress-bar]:bg-admin-accent"
          value={@upload_percent}
          max="100"
          data-test="upload-progress"
        >
        </progress>
      </div>

      <%!-- Step 1: File selection (no files chosen yet, not uploading) --%>
      <div :if={!@uploading && @upload_files == []} data-test="upload-file-picker">
        <div class="mb-4">
          <label
            class="mb-1 block font-ui text-sm font-medium text-admin-fg"
            for="upload-file"
          >
            Select video files
          </label>
          <input
            type="file"
            id="upload-file"
            name="video_file"
            accept="video/*"
            multiple
            class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
            data-test="upload-file"
          />
        </div>
      </div>

      <%!-- Step 2: Assign titles to each file --%>
      <form
        :if={!@uploading && @upload_files != []}
        id="upload-form"
        phx-submit="submit_upload"
        action="#"
        data-test="upload-form"
      >
        <p class="mb-3 font-body text-sm text-admin-muted">
          <span class="font-mono">{length(@upload_files)}</span>
          file(s) selected. Assign a title to each video:
        </p>

        <div class="mb-4 space-y-3">
          <div
            :for={file <- @upload_files}
            class="flex items-center gap-3"
            data-test={"upload-file-row-#{file.client_id}"}
          >
            <div
              class="w-32 flex-shrink-0 truncate font-mono text-xs text-admin-muted"
              title={file.name}
            >
              {file.name}
            </div>
            <input
              type="text"
              name={"titles[#{file.client_id}]"}
              value={file.title}
              class="w-full flex-1 rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
              placeholder="Video title"
              data-test={"upload-title-#{file.client_id}"}
            />
          </div>
        </div>
      </form>

      <:footer>
        <button
          type="button"
          phx-click="close_upload"
          class="inline-flex items-center justify-center gap-1.5 rounded-md px-4 py-2 font-ui text-sm font-medium text-admin-muted transition-colors hover:bg-admin-card hover:text-admin-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-admin-accent"
        >
          Cancel
        </button>
        <AdminUI.admin_button
          :if={!@uploading && @upload_files != []}
          type="submit"
          form="upload-form"
          data-test="upload-submit"
        >
          Upload {length(@upload_files)} Video{if length(@upload_files) > 1, do: "s", else: ""}
        </AdminUI.admin_button>
      </:footer>
    </AdminUI.admin_sheet>
    """
  end

  @doc """
  Renders the video detail view with edit form and tag management.
  """
  def video_detail(assigns) do
    ~H"""
    <div data-test="video-detail">
      <div class="mb-4 flex items-center gap-2">
        <AdminUI.admin_button
          variant={:ghost}
          size={:sm}
          phx-click="back_to_list"
          data-test="back-to-list-btn"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Back
        </AdminUI.admin_button>
      </div>

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <%!-- Video info panel --%>
        <div class="space-y-4 lg:col-span-2">
          <%!-- Video Player --%>
          <div
            :if={@video.mux_playback_id && @video.mux_status == "ready"}
            class="aspect-video w-full overflow-hidden rounded-lg bg-admin-card"
            data-test="admin-video-player"
          >
            <mux-player
              stream-type="on-demand"
              playback-id={@video.mux_playback_id}
              metadata-video-title={@video.title}
              thumbnail-time="0"
              style="width:100%;height:100%;display:block;"
              data-test="admin-mux-player"
            >
            </mux-player>
          </div>
          <%!-- Thumbnail fallback for non-ready videos --%>
          <div
            :if={@video.mux_playback_id && @video.mux_status != "ready"}
            class="aspect-video w-full overflow-hidden rounded-lg bg-admin-card"
          >
            <img
              src={"https://image.mux.com/#{@video.mux_playback_id}/thumbnail.webp?width=640&height=360"}
              alt={@video.title}
              class="h-full w-full object-cover"
            />
          </div>

          <%!-- Edit form --%>
          <div :if={@editing} data-test="video-edit-form">
            <form phx-submit="save_video" class="space-y-4">
              <div>
                <label class="mb-1 block font-ui text-sm font-medium text-admin-fg">
                  Title
                </label>
                <input
                  type="text"
                  name="video[title]"
                  value={@video.title}
                  class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                  data-test="video-title-input"
                />
              </div>
              <div>
                <label class="mb-1 block font-ui text-sm font-medium text-admin-fg">
                  Description
                </label>
                <textarea
                  name="video[description]"
                  class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                  rows="4"
                  data-test="video-description-input"
                >{@video.description}</textarea>
              </div>
              <div>
                <BobineWeb.Components.AdminComponents.image_upload_field
                  name="video[custom_thumbnail_url]"
                  kind="video_thumbnail"
                  target_id={@video.id}
                  url={@video_thumbnail_state.url}
                  status={@video_thumbnail_state.status}
                  percent={@video_thumbnail_state.percent}
                  error={@video_thumbnail_state.error}
                  label="Custom thumbnail"
                  help="Optional — overrides the Mux auto-generated thumbnail on cards."
                />
              </div>
              <div class="flex gap-2">
                <AdminUI.admin_button type="submit" size={:sm} data-test="save-video-btn">
                  Save
                </AdminUI.admin_button>
                <AdminUI.admin_button variant={:ghost} size={:sm} phx-click="cancel_edit">
                  Cancel
                </AdminUI.admin_button>
              </div>
            </form>
          </div>

          <%!-- Read-only info --%>
          <div :if={!@editing} class="space-y-2">
            <div class="flex items-center justify-between">
              <h2
                class="font-display text-xl font-semibold text-admin-fg"
                data-test="video-title"
              >
                {@video.title}
              </h2>
              <AdminUI.admin_button
                :if={@can_manage}
                variant={:secondary}
                size={:sm}
                phx-click="edit_video"
                data-test="edit-video-btn"
              >
                Edit
              </AdminUI.admin_button>
            </div>
            <p class="font-body text-admin-muted" data-test="video-description">
              {@video.description || "No description."}
            </p>
            <div class="flex gap-4 font-body text-sm text-admin-muted">
              <span>Status: <.status_badge status={@video.mux_status} /></span>
              <span>Duration: <span class="font-mono">{format_duration(@video.duration)}</span></span>
              <span>
                Uploaded:
                <span class="font-mono">
                  {Calendar.strftime(@video.inserted_at, "%b %d, %Y")}
                </span>
              </span>
            </div>
          </div>
        </div>

        <%!-- Tags sidebar --%>
        <div class="space-y-4" data-test="video-tags-panel">
          <div class="flex items-center justify-between">
            <h3 class="font-display font-semibold text-admin-fg">Tags</h3>
            <AdminUI.admin_button
              :if={@can_manage}
              variant={:secondary}
              size={:sm}
              phx-click="open_tag_picker"
              data-test="add-tag-btn"
            >
              Add Tag
            </AdminUI.admin_button>
          </div>

          <div
            :if={@video_tags == []}
            class="font-body text-sm text-admin-muted"
            data-test="no-tags"
          >
            No tags assigned.
          </div>

          <div :if={@video_tags != []} class="flex flex-wrap gap-2" data-test="video-tags-list">
            <span
              :for={tag <- @video_tags}
              class="inline-flex items-center gap-1 rounded-full bg-admin-card px-3 py-1 font-ui text-sm text-admin-fg"
              data-test={"video-tag-#{tag.id}"}
            >
              {tag.name}
              <button
                :if={@can_manage}
                type="button"
                phx-click="remove_tag"
                phx-value-tag-id={tag.id}
                class="rounded p-0.5 text-admin-muted hover:bg-admin-bg hover:text-admin-fg focus-visible:outline-2 focus-visible:outline-admin-accent"
                aria-label={"Remove tag #{tag.name}"}
                data-test={"remove-tag-#{tag.id}"}
              >
                <.icon name="hero-x-mark" class="size-3" />
              </button>
            </span>
          </div>

          <%!-- Tag picker --%>
          <div
            :if={@show_tag_picker}
            class="space-y-2 rounded-lg border border-admin-border bg-admin-bg p-3"
            data-test="tag-picker"
          >
            <p class="font-ui text-sm font-medium text-admin-fg">Select a tag:</p>
            <form phx-change="search_tags" phx-submit="search_tags">
              <input
                type="text"
                name="tag_search"
                value={@tag_search}
                placeholder="Search or create tag…"
                phx-debounce="200"
                class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                autocomplete="off"
                data-test="tag-search-input"
              />
            </form>
            <% filtered = filtered_available_tags(@all_tags, @video_tags, @tag_search) %>
            <AdminUI.admin_button
              :for={tag <- filtered}
              variant={:secondary}
              size={:sm}
              class="w-full justify-start"
              phx-click="add_tag"
              phx-value-tag-id={tag.id}
              data-test={"pick-tag-#{tag.id}"}
            >
              {tag.name}
            </AdminUI.admin_button>
            <AdminUI.admin_button
              :if={show_create_tag_button?(@all_tags, @tag_search)}
              size={:sm}
              class="w-full justify-start"
              phx-click="create_and_add_tag"
              phx-value-name={@tag_search}
              data-test="create-tag-btn"
            >
              Create "{@tag_search}"
            </AdminUI.admin_button>
            <div
              :if={filtered == [] && !show_create_tag_button?(@all_tags, @tag_search)}
              class="font-body text-sm text-admin-muted"
            >
              All tags assigned.
            </div>
            <AdminUI.admin_button
              variant={:ghost}
              size={:sm}
              phx-click="close_tag_picker"
              class="mt-2"
            >
              Cancel
            </AdminUI.admin_button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders inline tags for a video row with add/remove and search/create picker.
  """
  def row_tags(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-1">
      <span
        :for={tag <- @tags}
        class="inline-flex items-center gap-1 rounded-full bg-admin-card px-2 py-0.5 font-ui text-xs text-admin-fg"
        data-test={"row-tag-#{@video.id}-#{tag.id}"}
      >
        {tag.name}
        <button
          :if={@can_manage}
          type="button"
          phx-click="row_remove_tag"
          phx-value-tag-id={tag.id}
          phx-value-video-id={@video.id}
          class="rounded p-0.5 text-admin-muted hover:bg-admin-bg hover:text-admin-fg focus-visible:outline-2 focus-visible:outline-admin-accent"
          aria-label={"Remove tag #{tag.name}"}
          data-test={"row-remove-tag-#{@video.id}-#{tag.id}"}
        >
          <.icon name="hero-x-mark" class="size-3" />
        </button>
      </span>
      <button
        :if={@can_manage && !@picker_open}
        type="button"
        phx-click="open_row_tag_picker"
        phx-value-video-id={@video.id}
        class="rounded p-1 text-admin-muted hover:bg-admin-card hover:text-admin-fg focus-visible:outline-2 focus-visible:outline-admin-accent"
        aria-label="Add tag"
        data-test={"row-add-tag-#{@video.id}"}
      >
        <.icon name="hero-plus" class="size-3" />
      </button>

      <%!-- Inline tag picker --%>
      <div
        :if={@picker_open}
        class="absolute z-10 mt-1 w-64 space-y-2 rounded-lg border border-admin-border bg-admin-bg p-3 shadow-lg"
        data-test={"row-tag-picker-#{@video.id}"}
      >
        <form phx-change="search_tags" phx-submit="search_tags">
          <input
            type="text"
            name="tag_search"
            value={@tag_search}
            placeholder="Search or create tag…"
            phx-debounce="200"
            class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
            autocomplete="off"
            data-test={"row-tag-search-#{@video.id}"}
          />
        </form>
        <% filtered = filtered_available_tags(@all_tags, @tags, @tag_search) %>
        <AdminUI.admin_button
          :for={tag <- filtered}
          variant={:secondary}
          size={:sm}
          class="w-full justify-start"
          phx-click="row_add_tag"
          phx-value-tag-id={tag.id}
          phx-value-video-id={@video.id}
          data-test={"row-pick-tag-#{@video.id}-#{tag.id}"}
        >
          {tag.name}
        </AdminUI.admin_button>
        <AdminUI.admin_button
          :if={show_create_tag_button?(@all_tags, @tag_search)}
          size={:sm}
          class="w-full justify-start"
          phx-click="row_create_and_add_tag"
          phx-value-name={@tag_search}
          phx-value-video-id={@video.id}
          data-test={"row-create-tag-#{@video.id}"}
        >
          Create "{@tag_search}"
        </AdminUI.admin_button>
        <AdminUI.admin_button
          variant={:ghost}
          size={:sm}
          class="mt-2"
          phx-click="close_row_tag_picker"
        >
          Cancel
        </AdminUI.admin_button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a colored status badge for a Mux video status.
  """
  def status_badge(%{status: "ready"} = assigns) do
    ~H"""
    <span class="inline-flex items-center rounded-full border border-success/40 bg-success/10 px-2 py-0.5 font-ui text-xs font-medium text-success">
      Ready
    </span>
    """
  end

  def status_badge(%{status: "preparing"} = assigns) do
    ~H"""
    <span class="inline-flex items-center rounded-full border border-warning/40 bg-warning/10 px-2 py-0.5 font-ui text-xs font-medium text-warning">
      Processing
    </span>
    """
  end

  def status_badge(%{status: "waiting"} = assigns) do
    ~H"""
    <span class="inline-flex items-center rounded-full bg-admin-accent/10 px-2 py-0.5 font-ui text-xs font-medium text-admin-accent">
      Uploading
    </span>
    """
  end

  def status_badge(%{status: "errored"} = assigns) do
    ~H"""
    <span class="inline-flex items-center rounded-full border border-error/40 bg-error/10 px-2 py-0.5 font-ui text-xs font-medium text-error">
      Error
    </span>
    """
  end

  def status_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center rounded-full bg-admin-card px-2 py-0.5 font-ui text-xs font-medium text-admin-muted">
      {@status}
    </span>
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

  @doc """
  Returns available tags filtered by a search term.

      iex> all = [%{id: 1, name: "yoga"}, %{id: 2, name: "beginner"}]
      iex> assigned = []
      iex> BobineWeb.Admin.ContentLive.Components.filtered_available_tags(all, assigned, "yog")
      [%{id: 1, name: "yoga"}]

      iex> all = [%{id: 1, name: "yoga"}]
      iex> BobineWeb.Admin.ContentLive.Components.filtered_available_tags(all, [], "")
      [%{id: 1, name: "yoga"}]
  """
  def filtered_available_tags(all_tags, video_tags, search) do
    all_tags
    |> available_tags(video_tags)
    |> filter_tags_by_search(search)
  end

  @doc """
  Returns true when the search term is non-empty and no existing tag
  matches it exactly (case-insensitive).

      iex> tags = [%{id: 1, name: "yoga"}]
      iex> BobineWeb.Admin.ContentLive.Components.show_create_tag_button?(tags, "pilates")
      true

      iex> tags = [%{id: 1, name: "yoga"}]
      iex> BobineWeb.Admin.ContentLive.Components.show_create_tag_button?(tags, "Yoga")
      false

      iex> tags = [%{id: 1, name: "yoga"}]
      iex> BobineWeb.Admin.ContentLive.Components.show_create_tag_button?(tags, "")
      false
  """
  def show_create_tag_button?(_all_tags, ""), do: false

  def show_create_tag_button?(all_tags, search) do
    normalized = String.downcase(String.trim(search))

    normalized != "" &&
      not Enum.any?(all_tags, fn tag -> String.downcase(tag.name) == normalized end)
  end

  defp filter_tags_by_search(tags, ""), do: tags

  defp filter_tags_by_search(tags, search) do
    normalized = String.downcase(String.trim(search))
    Enum.filter(tags, fn tag -> String.contains?(String.downcase(tag.name), normalized) end)
  end
end
