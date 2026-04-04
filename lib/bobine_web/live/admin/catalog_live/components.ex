defmodule BobineWeb.Admin.CatalogLive.Components do
  @moduledoc """
  Extracted template components for the Catalog LiveView.

  Contains hero editor, rows list, row form, row preview, and row items view
  components along with their helper functions.
  """

  use BobineWeb, :html

  @doc """
  Renders a label for a given source type atom.

  ## Examples

      iex> BobineWeb.Admin.CatalogLive.Components.source_type_label(:curated)
      "Curated"

      iex> BobineWeb.Admin.CatalogLive.Components.source_type_label(:collection)
      "Collection"

      iex> BobineWeb.Admin.CatalogLive.Components.source_type_label(:hero)
      "Hero"
  """
  def source_type_label(:curated), do: "Curated"
  def source_type_label(:collection), do: "Collection"
  def source_type_label(:tag), do: "Tag"
  def source_type_label(:recent), do: "Recent"
  def source_type_label(:popular), do: "Popular"
  def source_type_label(:continue_watching), do: "Continue Watching"
  def source_type_label(:hero), do: "Hero"
  def source_type_label(other), do: to_string(other)

  @doc """
  Returns true when the current source type matches the target source type.

  ## Examples

      iex> BobineWeb.Admin.CatalogLive.Components.show_source_select?(:collection, :collection)
      true

      iex> BobineWeb.Admin.CatalogLive.Components.show_source_select?("tag", :tag)
      true

      iex> BobineWeb.Admin.CatalogLive.Components.show_source_select?(:curated, :collection)
      false
  """
  def show_source_select?(current, target) do
    to_string(current) == to_string(target)
  end

  @doc """
  Extracts the auto-advance millisecond value from a hero row's filter config.

  ## Examples

      iex> BobineWeb.Admin.CatalogLive.Components.hero_auto_advance_ms(%{filter_config: %{"auto_advance_ms" => 5000}})
      5000

      iex> BobineWeb.Admin.CatalogLive.Components.hero_auto_advance_ms(%{filter_config: %{}})
      8000

      iex> BobineWeb.Admin.CatalogLive.Components.hero_auto_advance_ms(%{})
      8000
  """
  def hero_auto_advance_ms(%{filter_config: config}) when is_map(config) do
    Map.get(config, "auto_advance_ms", 8000)
  end

  def hero_auto_advance_ms(_), do: 8000

  @doc """
  Hero carousel editor component.

  Displays hero slide management UI including add/remove/reorder slides,
  auto-advance configuration, and a video picker modal.
  """
  attr :hero_row, :map, required: true
  attr :hero_slides, :list, required: true
  attr :can_manage, :boolean, required: true
  attr :show_hero_video_picker, :boolean, required: true
  attr :hero_available_videos, :list, required: true
  attr :hero_save_status, :map, required: true
  attr :hero_collapsed, :boolean, required: true

  def hero_editor(assigns) do
    ~H"""
    <div data-test="hero-editor">
      <div class="flex items-center justify-between pb-4">
        <button
          phx-click="toggle_hero_collapsed"
          class="flex items-center gap-2 cursor-pointer bg-transparent border-none p-0"
          aria-expanded={to_string(!@hero_collapsed)}
          aria-controls="hero-editor-body"
          data-test="hero-collapse-toggle"
        >
          <.icon
            name={if @hero_collapsed, do: "hero-chevron-right", else: "hero-chevron-down"}
            class="size-5"
          />
          <.header>Hero Carousel</.header>
        </button>
        <%= if @hero_row do %>
          <div class="flex items-center gap-2">
            <button
              :if={@can_manage}
              phx-click="toggle_hero_visibility"
              data-test="hero-visibility-toggle"
              class={"badge badge-sm #{if @hero_row.visible, do: "badge-success", else: "badge-ghost"}"}
            >
              {if @hero_row.visible, do: "Visible", else: "Hidden"}
            </button>
          </div>
        <% end %>
      </div>

      <div :if={!@hero_collapsed} id="hero-editor-body">
        <%= if is_nil(@hero_row) do %>
          <div class="py-8 text-center bg-base-200 rounded-lg">
            <p class="text-base-content/60 mb-4">
              Create a hero carousel to feature up to 4 items at the top of your homepage.
            </p>
            <button
              :if={@can_manage}
              phx-click="create_hero"
              class="btn btn-primary"
              data-test="create-hero-btn"
            >
              Create hero carousel
            </button>
          </div>
        <% else %>
          <%!-- Auto-advance config --%>
          <div :if={@can_manage} class="flex items-center gap-4 mb-4 p-3 bg-base-200 rounded-lg">
            <label for="hero-auto-advance" class="text-sm font-medium">Auto-rotate:</label>
            <form phx-submit="save_hero_auto_advance" class="flex items-center gap-2">
              <select
                id="hero-auto-advance"
                name="auto_advance_ms"
                class="select select-bordered select-sm"
                data-test="hero-auto-advance-select"
              >
                <option value="0" selected={hero_auto_advance_ms(@hero_row) == 0}>
                  Disabled
                </option>
                <option value="5000" selected={hero_auto_advance_ms(@hero_row) == 5000}>
                  5 seconds
                </option>
                <option value="8000" selected={hero_auto_advance_ms(@hero_row) == 8000}>
                  8 seconds
                </option>
                <option value="10000" selected={hero_auto_advance_ms(@hero_row) == 10_000}>
                  10 seconds
                </option>
                <option value="15000" selected={hero_auto_advance_ms(@hero_row) == 15_000}>
                  15 seconds
                </option>
              </select>
              <button
                type="submit"
                class="btn btn-sm btn-primary"
                phx-disable-with="Saving..."
                data-test="hero-auto-advance-save-btn"
              >
                Save
              </button>
              <span
                :if={@hero_save_status["auto_advance"] == :ok}
                class="text-sm text-success flex items-center gap-1"
                data-test="hero-auto-advance-save-success"
                role="status"
              >
                <.icon name="hero-check-circle" class="size-4" /> Saved
              </span>
            </form>
          </div>

          <div class="space-y-4">
            <%!-- Existing slides --%>
            <div
              :for={slide <- @hero_slides}
              class="p-4 bg-base-200 rounded-lg"
              data-test={"hero-slide-editor-#{slide.position}"}
            >
              <div class="flex items-start justify-between mb-3">
                <div class="flex items-center gap-2">
                  <span class="badge badge-sm">Slide {slide.position + 1}</span>
                  <span class="text-sm text-base-content/60">
                    Video: {slide.video_title}
                  </span>
                </div>
                <div :if={@can_manage} class="flex gap-1">
                  <button
                    phx-click="move_hero_slide_up"
                    phx-value-slide-id={slide.id}
                    class="btn btn-xs btn-ghost"
                    aria-label="Move slide up"
                  >
                    ↑
                  </button>
                  <button
                    phx-click="move_hero_slide_down"
                    phx-value-slide-id={slide.id}
                    class="btn btn-xs btn-ghost"
                    aria-label="Move slide down"
                  >
                    ↓
                  </button>
                  <button
                    phx-click="remove_hero_slide"
                    phx-value-slide-id={slide.id}
                    class="btn btn-xs btn-outline btn-error"
                    data-test={"hero-remove-slide-#{slide.position}"}
                  >
                    Remove
                  </button>
                </div>
              </div>

              <form phx-submit="save_hero_slide" class="grid grid-cols-2 gap-3">
                <input type="hidden" name="slide-id" value={slide.id} />
                <div>
                  <label class="label text-xs">Headline</label>
                  <input
                    type="text"
                    name="headline"
                    value={slide.headline}
                    placeholder={slide.video_title}
                    class="input input-bordered input-sm w-full"
                    data-test={"hero-headline-input-#{slide.position}"}
                  />
                </div>
                <div>
                  <label class="label text-xs">Subheadline</label>
                  <input
                    type="text"
                    name="subheadline"
                    value={slide.subheadline}
                    placeholder="optional"
                    class="input input-bordered input-sm w-full"
                    data-test={"hero-subheadline-input-#{slide.position}"}
                  />
                </div>
                <div>
                  <label class="label text-xs">Brand Tag</label>
                  <input
                    type="text"
                    name="brand_tag"
                    value={slide.brand_tag}
                    placeholder="optional"
                    class="input input-bordered input-sm w-full"
                    data-test={"hero-brand-tag-input-#{slide.position}"}
                  />
                </div>
                <div>
                  <label class="label text-xs">Primary CTA Label</label>
                  <input
                    type="text"
                    name="primary_cta_label"
                    value={slide.primary_cta_label}
                    placeholder="Watch now"
                    class="input input-bordered input-sm w-full"
                    data-test={"hero-primary-cta-input-#{slide.position}"}
                  />
                </div>
                <div>
                  <label class="label text-xs">Secondary CTA Label</label>
                  <input
                    type="text"
                    name="secondary_cta_label"
                    value={slide.secondary_cta_label}
                    placeholder="More info"
                    class="input input-bordered input-sm w-full"
                    data-test={"hero-secondary-cta-input-#{slide.position}"}
                  />
                </div>
                <div>
                  <label class="label text-xs">Custom Background URL</label>
                  <input
                    type="text"
                    name="background_image_url"
                    value={slide.background_image_url}
                    placeholder="Uses video thumbnail if empty"
                    class="input input-bordered input-sm w-full"
                    data-test={"hero-bg-url-input-#{slide.position}"}
                  />
                </div>
                <div class="col-span-2">
                  <label class="label text-xs">Description</label>
                  <textarea
                    name="description"
                    placeholder={slide.video_description || "optional"}
                    rows="2"
                    class="textarea textarea-bordered textarea-sm w-full"
                    data-test={"hero-description-input-#{slide.position}"}
                  >{slide.description}</textarea>
                </div>
                <div class="col-span-2 flex items-center justify-end gap-2">
                  <span
                    :if={@hero_save_status[slide.id] == :ok}
                    class="text-sm text-success flex items-center gap-1"
                    data-test={"hero-slide-save-success-#{slide.position}"}
                    role="status"
                  >
                    <.icon name="hero-check-circle" class="size-4" /> Saved
                  </span>
                  <span
                    :if={@hero_save_status[slide.id] == :error}
                    class="text-sm text-error flex items-center gap-1"
                    data-test={"hero-slide-save-error-#{slide.position}"}
                    role="alert"
                  >
                    <.icon name="hero-exclamation-circle" class="size-4" /> Save failed
                  </span>
                  <button
                    :if={@can_manage}
                    type="submit"
                    class="btn btn-sm btn-primary"
                    phx-disable-with="Saving..."
                    data-test={"hero-slide-save-btn-#{slide.position}"}
                  >
                    Save
                  </button>
                </div>
              </form>
            </div>

            <%!-- Add slide button --%>
            <div :if={@can_manage && length(@hero_slides) < 4}>
              <button
                phx-click="open_hero_video_picker"
                class="btn btn-outline btn-sm w-full"
                data-test="hero-add-slide-btn"
              >
                + Add slide ({length(@hero_slides)}/4)
              </button>
            </div>

            <div
              :if={@can_manage && length(@hero_slides) >= 4}
              class="text-center text-sm text-base-content/50"
            >
              Maximum of 4 slides reached.
            </div>
          </div>

          <%!-- Hero video picker modal --%>
          <div
            :if={@show_hero_video_picker}
            class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
          >
            <div class="bg-base-100 rounded-lg p-6 w-full max-w-lg shadow-xl max-h-[80vh] overflow-y-auto">
              <div class="flex items-center justify-between mb-4">
                <h3 class="text-lg font-semibold">Select a Video for Hero Slide</h3>
                <button
                  phx-click="close_hero_video_picker"
                  class="btn btn-ghost btn-sm"
                  aria-label="Close"
                >
                  ✕
                </button>
              </div>
              <div
                :if={@hero_available_videos == []}
                class="py-4 text-center text-base-content/60"
              >
                No available videos.
              </div>
              <div :if={@hero_available_videos != []} class="space-y-2">
                <div
                  :for={video <- @hero_available_videos}
                  class="flex items-center justify-between p-2 bg-base-200 rounded"
                >
                  <span class="truncate" data-test={"hero-video-select-#{video.id}"}>
                    {video.title}
                  </span>
                  <button
                    phx-click="add_hero_slide"
                    phx-value-video-id={video.id}
                    class="btn btn-xs btn-primary"
                  >
                    Select
                  </button>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders the rows list view with a table of content rows, visibility toggles,
  reordering controls, and action buttons.
  """
  attr :rows, :list, required: true
  attr :can_manage, :boolean, required: true
  attr :show_form, :boolean, required: true
  attr :form, :map, required: true
  attr :editing_row, :map, required: true
  attr :source_types, :list, required: true
  attr :collections, :list, required: true
  attr :tags, :list, required: true
  attr :selected_row, :map, required: true
  attr :preview_videos, :list, required: true

  def rows_list_view(assigns) do
    ~H"""
    <div class="flex items-center justify-between pb-4">
      <.header>Content Rows</.header>
      <button
        :if={@can_manage}
        phx-click="new_row"
        class="btn btn-primary"
        data-test="new-row-btn"
      >
        New Row
      </button>
    </div>

    <div
      :if={@rows == []}
      class="py-12 text-center text-base-content/60"
      data-test="empty-state"
    >
      <p class="text-lg">No catalog rows yet.</p>
      <p class="mt-2">Create rows to build your viewer homepage.</p>
    </div>

    <div :if={@rows != []} data-test="rows-list" class="overflow-x-auto">
      <table class="table w-full">
        <thead>
          <tr>
            <th>Title</th>
            <th>Source</th>
            <th>Visible</th>
            <th>Order</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} data-test={"row-#{row.id}"}>
            <td class="font-medium">{row.title}</td>
            <td>
              <span class="badge badge-sm badge-outline">
                {source_type_label(row.source_type)}
              </span>
            </td>
            <td>
              <button
                :if={@can_manage}
                phx-click="toggle_visibility"
                phx-value-id={row.id}
                data-test="row-visibility-toggle"
                class={"badge badge-sm #{if row.visible, do: "badge-success", else: "badge-ghost"}"}
              >
                {if row.visible, do: "Visible", else: "Hidden"}
              </button>
            </td>
            <td class="flex gap-1">
              <button
                :if={@can_manage}
                phx-click="move_up"
                phx-value-id={row.id}
                class="btn btn-xs btn-ghost"
                aria-label="Move row up"
              >
                ↑
              </button>
              <button
                :if={@can_manage}
                phx-click="move_down"
                phx-value-id={row.id}
                class="btn btn-xs btn-ghost"
                aria-label="Move row down"
              >
                ↓
              </button>
            </td>
            <td :if={@can_manage}>
              <div class="flex gap-1">
                <button
                  phx-click="preview_row"
                  phx-value-id={row.id}
                  class="btn btn-xs btn-outline"
                  data-test="row-preview"
                >
                  Preview
                </button>
                <button
                  :if={row.source_type == :curated}
                  phx-click="manage_items"
                  phx-value-id={row.id}
                  class="btn btn-xs btn-outline"
                >
                  Items
                </button>
                <button
                  phx-click="edit_row"
                  phx-value-id={row.id}
                  class="btn btn-xs btn-outline"
                >
                  Edit
                </button>
                <button
                  phx-click="delete_row"
                  phx-value-id={row.id}
                  data-confirm="Are you sure?"
                  class="btn btn-xs btn-outline btn-error"
                  data-test={"delete-row-#{row.id}"}
                >
                  Delete
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <.row_preview
      :if={@selected_row && @preview_videos != []}
      row={@selected_row}
      videos={@preview_videos}
    />
    <.row_form
      :if={@show_form}
      form={@form}
      editing={@editing_row}
      source_types={@source_types}
      collections={@collections}
      tags={@tags}
    />
    """
  end

  @doc """
  Renders the row creation/editing form modal.
  """
  attr :form, :map, required: true
  attr :editing, :map, required: true
  attr :source_types, :list, required: true
  attr :collections, :list, required: true
  attr :tags, :list, required: true

  def row_form(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div class="bg-base-100 rounded-lg p-6 w-full max-w-md shadow-xl">
        <h3 class="text-lg font-semibold mb-4">
          {if @editing, do: "Edit Row", else: "New Row"}
        </h3>
        <.form for={@form} phx-submit="save_row" data-test="row-form">
          <div class="mb-4">
            <label class="label" for="row-title">Title</label>
            <input
              type="text"
              id="row-title"
              name="row[title]"
              value={@form[:title].value}
              required
              class="input input-bordered w-full"
              data-test="row-title-input"
            />
          </div>
          <div class="mb-4">
            <label class="label" for="row-source-type">Source Type</label>
            <select
              id="row-source-type"
              name="row[source_type]"
              class="select select-bordered w-full"
              data-test="row-source-type-select"
            >
              <option
                :for={{label, value} <- @source_types}
                value={value}
                selected={to_string(@form[:source_type].value) == value}
              >
                {label}
              </option>
            </select>
          </div>
          <div :if={show_source_select?(@form[:source_type].value, :collection)} class="mb-4">
            <label class="label" for="row-collection-select">Collection</label>
            <select
              id="row-collection-select"
              name="row[source_id]"
              class="select select-bordered w-full"
              data-test="row-source-id-select"
            >
              <option value="">Select a collection...</option>
              <option
                :for={c <- @collections}
                value={c.id}
                selected={@form[:source_id].value == c.id}
              >
                {c.title}
              </option>
            </select>
          </div>
          <div :if={show_source_select?(@form[:source_type].value, :tag)} class="mb-4">
            <label class="label" for="row-tag-select">Tag</label>
            <select
              id="row-tag-select"
              name="row[source_id]"
              class="select select-bordered w-full"
              data-test="row-source-id-select"
            >
              <option value="">Select a tag...</option>
              <option
                :for={t <- @tags}
                value={t.id}
                selected={@form[:source_id].value == t.id}
              >
                {t.name}
              </option>
            </select>
          </div>
          <div class="mb-4">
            <label class="label" for="row-max-items">Max Items</label>
            <input
              type="number"
              id="row-max-items"
              name="row[max_items]"
              value={@form[:max_items].value || 20}
              min="5"
              max="50"
              class="input input-bordered w-full"
            />
          </div>
          <div class="flex justify-end gap-2">
            <button type="button" phx-click="cancel_form" class="btn btn-ghost">Cancel</button>
            <button type="submit" class="btn btn-primary">Save</button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @doc """
  Renders a preview modal showing a horizontal scroll of video thumbnails for a row.
  """
  attr :row, :map, required: true
  attr :videos, :list, required: true

  def row_preview(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div class="bg-base-100 rounded-lg p-6 w-full max-w-2xl shadow-xl" data-test="row-preview">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold">Preview: {@row.title}</h3>
          <button phx-click="close_preview" class="btn btn-ghost btn-sm" aria-label="Close">✕</button>
        </div>
        <div class="flex gap-3 overflow-x-auto pb-2">
          <div :for={video <- @videos} class="flex-shrink-0 w-40">
            <div class="w-40 h-24 rounded bg-base-300 overflow-hidden">
              <img
                :if={video.mux_playback_id}
                src={"https://image.mux.com/#{video.mux_playback_id}/thumbnail.webp?width=320&height=192"}
                alt={video.title}
                class="w-full h-full object-cover"
              />
            </div>
            <p class="text-sm mt-1 truncate">{video.title}</p>
          </div>
        </div>
        <div :if={@videos == []} class="py-4 text-center text-base-content/60">
          No videos to preview.
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the curated row items management view with add/remove video controls.
  """
  attr :row, :map, required: true
  attr :videos, :list, required: true
  attr :can_manage, :boolean, required: true
  attr :show_video_picker, :boolean, required: true
  attr :available_videos, :list, required: true

  def row_items_view(assigns) do
    ~H"""
    <div class="flex items-center justify-between pb-4">
      <div class="flex items-center gap-3">
        <button phx-click="back_from_manage" class="btn btn-ghost btn-sm">← Back</button>
        <.header>{@row.title} — Items</.header>
      </div>
      <button
        :if={@can_manage}
        phx-click="open_video_picker"
        class="btn btn-primary btn-sm"
        data-test="add-videos-btn"
      >
        Add Videos
      </button>
    </div>

    <div :if={@videos == []} class="py-8 text-center text-base-content/60">
      <p>No items in this row yet.</p>
    </div>

    <div :if={@videos != []} class="space-y-2">
      <div
        :for={video <- @videos}
        class="flex items-center gap-3 p-3 bg-base-200 rounded-lg"
      >
        <div class="flex-1 font-medium truncate">{video.title}</div>
        <div :if={@can_manage} class="flex gap-1">
          <button
            phx-click="remove_video_from_row"
            phx-value-video-id={video.id}
            class="btn btn-xs btn-outline btn-error"
          >
            Remove
          </button>
        </div>
      </div>
    </div>

    <div
      :if={@show_video_picker}
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    >
      <div class="bg-base-100 rounded-lg p-6 w-full max-w-lg shadow-xl max-h-[80vh] overflow-y-auto">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold">Add Videos</h3>
          <button phx-click="close_video_picker" class="btn btn-ghost btn-sm" aria-label="Close">
            ✕
          </button>
        </div>
        <div :if={@available_videos == []} class="py-4 text-center text-base-content/60">
          All videos are already in this row.
        </div>
        <div :if={@available_videos != []} class="space-y-2">
          <div
            :for={video <- @available_videos}
            class="flex items-center justify-between p-2 bg-base-200 rounded"
          >
            <span class="truncate">{video.title}</span>
            <button
              phx-click="add_video_to_row"
              phx-value-video-id={video.id}
              class="btn btn-xs btn-primary"
            >
              Add
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
