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
  def source_type_label(:new_seasons), do: "New seasons"
  def source_type_label(:popularity), do: "Popularity"
  def source_type_label(:tags), do: "Tags"
  def source_type_label(:preferences), do: "Preferences"
  def source_type_label(:series), do: "Series"
  def source_type_label(:creator_showcase), do: "Creator showcase"
  def source_type_label(:editorial_spotlight), do: "Editorial spotlight"
  def source_type_label(other), do: to_string(other)

  @doc """
  Returns card variant options compatible with a row's source_type as
  `{label, value}` tuples suitable for an HTML select. Prepends a blank
  option so operators can clear the variant and fall back to default.
  """
  def card_variant_options(source_type) when is_atom(source_type) and not is_nil(source_type) do
    row_type = Bobine.Catalog.Row.compat_row_type(source_type)

    variants = Bobine.Catalog.Presets.variants_for_row(row_type)

    [{"Default", ""} | Enum.map(variants, &{card_variant_label(&1), Atom.to_string(&1)})]
  end

  def card_variant_options(source_type) when is_binary(source_type) do
    source_type
    |> String.to_existing_atom()
    |> card_variant_options()
  rescue
    ArgumentError -> [{"Default", ""}]
  end

  def card_variant_options(_), do: [{"Default", ""}]

  @doc """
  Human label for a card variant atom.

      iex> BobineWeb.Admin.CatalogLive.Components.card_variant_label(:poster_portrait)
      "Poster portrait"
  """
  def card_variant_label(:poster_portrait), do: "Poster portrait"
  def card_variant_label(:landscape_episode), do: "Landscape episode"
  def card_variant_label(:creator_identity), do: "Creator identity"
  def card_variant_label(:collection_editorial), do: "Collection editorial"
  def card_variant_label(:progress_course), do: "Progress course"
  def card_variant_label(:minimal_list_item), do: "Minimal list item"
  def card_variant_label(other), do: to_string(other)

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
              class={"rounded-full px-2 py-0.5 font-ui text-xs #{if @hero_row.visible, do: "bg-success/20 text-success", else: "bg-admin-elevated text-admin-text-muted"}"}
            >
              {if @hero_row.visible, do: "Visible", else: "Hidden"}
            </button>
          </div>
        <% end %>
      </div>

      <div :if={!@hero_collapsed} id="hero-editor-body">
        <%= if is_nil(@hero_row) do %>
          <div class="py-8 text-center bg-admin-bg rounded-lg">
            <p class="text-admin-text-muted mb-4">
              Create a hero carousel to feature up to 4 items at the top of your homepage.
            </p>
            <button
              :if={@can_manage}
              phx-click="create_hero"
              class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-4 py-2 font-ui text-sm font-medium text-admin-accent-text hover:bg-admin-accent-hover"
              data-test="create-hero-btn"
            >
              Create hero carousel
            </button>
          </div>
        <% else %>
          <%!-- Auto-advance config --%>
          <div :if={@can_manage} class="flex items-center gap-4 mb-4 p-3 bg-admin-bg rounded-lg">
            <label for="hero-auto-advance" class="text-sm font-medium">Auto-rotate:</label>
            <form phx-submit="save_hero_auto_advance" class="flex items-center gap-2">
              <select
                id="hero-auto-advance"
                name="auto_advance_ms"
                class="w-auto rounded-md border border-admin-border bg-admin-elevated px-2 py-1 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
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
                class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-3 py-1.5 font-ui text-sm font-medium text-admin-accent-text hover:bg-admin-accent-hover"
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
              class="p-4 bg-admin-bg rounded-lg"
              data-test={"hero-slide-editor-#{slide.position}"}
            >
              <div class="flex items-start justify-between mb-3">
                <div class="flex items-center gap-2">
                  <span class="rounded-full bg-admin-elevated px-2 py-0.5 font-ui text-xs text-admin-text-secondary">Slide {slide.position + 1}</span>
                  <span class="text-sm text-admin-text-muted">
                    Video: {slide.video_title}
                  </span>
                </div>
                <div :if={@can_manage} class="flex gap-1">
                  <button
                    phx-click="move_hero_slide_up"
                    phx-value-slide-id={slide.id}
                    class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-text-secondary hover:bg-admin-elevated hover:text-admin-text-primary"
                    aria-label="Move slide up"
                  >
                    ↑
                  </button>
                  <button
                    phx-click="move_hero_slide_down"
                    phx-value-slide-id={slide.id}
                    class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-text-secondary hover:bg-admin-elevated hover:text-admin-text-primary"
                    aria-label="Move slide down"
                  >
                    ↓
                  </button>
                  <button
                    phx-click="remove_hero_slide"
                    phx-value-slide-id={slide.id}
                    class="inline-flex items-center gap-1.5 rounded-md border border-error px-2 py-1 font-ui text-xs font-medium text-error hover:bg-error hover:text-admin-accent-text"
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
                    class="w-full rounded-md border border-admin-border bg-admin-elevated px-2 py-1 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
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
                    class="w-full rounded-md border border-admin-border bg-admin-elevated px-2 py-1 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
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
                    class="w-full rounded-md border border-admin-border bg-admin-elevated px-2 py-1 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
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
                    class="w-full rounded-md border border-admin-border bg-admin-elevated px-2 py-1 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
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
                    class="w-full rounded-md border border-admin-border bg-admin-elevated px-2 py-1 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
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
                    class="w-full rounded-md border border-admin-border bg-admin-elevated px-2 py-1 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
                    data-test={"hero-bg-url-input-#{slide.position}"}
                  />
                </div>
                <div class="col-span-2">
                  <label class="label text-xs">Description</label>
                  <textarea
                    name="description"
                    placeholder={slide.video_description || "optional"}
                    rows="2"
                    class="w-full rounded-md border border-admin-border bg-admin-elevated px-2 py-1 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
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
                    class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-3 py-1.5 font-ui text-sm font-medium text-admin-accent-text hover:bg-admin-accent-hover"
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
                class="inline-flex w-full items-center justify-center gap-1.5 rounded-md border border-admin-border px-3 py-1.5 font-ui text-sm font-medium text-admin-text-primary hover:border-admin-border-strong"
                data-test="hero-add-slide-btn"
              >
                + Add slide ({length(@hero_slides)}/4)
              </button>
            </div>

            <div
              :if={@can_manage && length(@hero_slides) >= 4}
              class="text-center text-sm text-admin-text-muted"
            >
              Maximum of 4 slides reached.
            </div>
          </div>

          <%!-- Hero video picker modal --%>
          <div
            :if={@show_hero_video_picker}
            class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
          >
            <div class="bg-admin-surface rounded-lg p-6 w-full max-w-lg shadow-xl max-h-[80vh] overflow-y-auto">
              <div class="flex items-center justify-between mb-4">
                <h3 class="text-lg font-semibold">Select a Video for Hero Slide</h3>
                <button
                  phx-click="close_hero_video_picker"
                  class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-text-secondary hover:bg-admin-elevated hover:text-admin-text-primary"
                  aria-label="Close"
                >
                  ✕
                </button>
              </div>
              <div
                :if={@hero_available_videos == []}
                class="py-4 text-center text-admin-text-muted"
              >
                No available videos.
              </div>
              <div :if={@hero_available_videos != []} class="space-y-2">
                <div
                  :for={video <- @hero_available_videos}
                  class="flex items-center justify-between p-2 bg-admin-bg rounded"
                >
                  <span class="truncate" data-test={"hero-video-select-#{video.id}"}>
                    {video.title}
                  </span>
                  <button
                    phx-click="add_hero_slide"
                    phx-value-video-id={video.id}
                    class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-2 py-1 font-ui text-xs font-medium text-admin-accent-text hover:bg-admin-accent-hover"
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
        class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-4 py-2 font-ui text-sm font-medium text-admin-accent-text hover:bg-admin-accent-hover"
        data-test="new-row-btn"
      >
        New Row
      </button>
    </div>

    <div
      :if={@rows == []}
      class="py-12 text-center text-admin-text-muted"
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
            <th>Card variant</th>
            <th>Visible</th>
            <th>Order</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} data-test={"row-#{row.id}"}>
            <td class="font-medium">{row.title}</td>
            <td>
              <span class="rounded-full border border-admin-border px-2 py-0.5 font-ui text-xs text-admin-text-secondary">
                {source_type_label(row.source_type)}
              </span>
            </td>
            <td>
              <form
                :if={@can_manage}
                phx-change="update_row_variant"
                class="flex items-center gap-2"
              >
                <input type="hidden" name="row_id" value={row.id} />
                <select
                  name="variant"
                  class="w-auto rounded-md border border-admin-border bg-admin-elevated px-2 py-1 font-body text-xs text-admin-text-primary focus:border-admin-accent focus:outline-none"
                  data-test={"row-variant-#{row.id}"}
                >
                  <option
                    :for={{label, value} <- card_variant_options(row.source_type)}
                    value={value}
                    selected={to_string(row.card_variant || "") == value}
                  >
                    {label}
                  </option>
                </select>
              </form>
              <span
                :if={!@can_manage}
                class="text-xs text-admin-text-muted"
              >
                {card_variant_label(row.card_variant || :default)}
              </span>
            </td>
            <td>
              <button
                :if={@can_manage}
                phx-click="toggle_visibility"
                phx-value-id={row.id}
                data-test="row-visibility-toggle"
                class={"rounded-full px-2 py-0.5 font-ui text-xs #{if row.visible, do: "bg-success/20 text-success", else: "bg-admin-elevated text-admin-text-muted"}"}
              >
                {if row.visible, do: "Visible", else: "Hidden"}
              </button>
            </td>
            <td class="flex gap-1">
              <button
                :if={@can_manage}
                phx-click="move_up"
                phx-value-id={row.id}
                class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-text-secondary hover:bg-admin-elevated hover:text-admin-text-primary"
                aria-label="Move row up"
              >
                ↑
              </button>
              <button
                :if={@can_manage}
                phx-click="move_down"
                phx-value-id={row.id}
                class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-text-secondary hover:bg-admin-elevated hover:text-admin-text-primary"
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
                  class="inline-flex items-center gap-1.5 rounded-md border border-admin-border px-2 py-1 font-ui text-xs font-medium text-admin-text-primary hover:border-admin-border-strong"
                  data-test="row-preview"
                >
                  Preview
                </button>
                <button
                  :if={row.source_type == :curated}
                  phx-click="manage_items"
                  phx-value-id={row.id}
                  class="inline-flex items-center gap-1.5 rounded-md border border-admin-border px-2 py-1 font-ui text-xs font-medium text-admin-text-primary hover:border-admin-border-strong"
                >
                  Items
                </button>
                <button
                  phx-click="edit_row"
                  phx-value-id={row.id}
                  class="inline-flex items-center gap-1.5 rounded-md border border-admin-border px-2 py-1 font-ui text-xs font-medium text-admin-text-primary hover:border-admin-border-strong"
                >
                  Edit
                </button>
                <button
                  phx-click="delete_row"
                  phx-value-id={row.id}
                  data-confirm="Are you sure?"
                  class="inline-flex items-center gap-1.5 rounded-md border border-error px-2 py-1 font-ui text-xs font-medium text-error hover:bg-error hover:text-admin-accent-text"
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
      <div class="bg-admin-surface rounded-lg p-6 w-full max-w-md shadow-xl">
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
              class="w-full rounded-md border border-admin-border bg-admin-elevated px-3 py-2 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
              data-test="row-title-input"
            />
          </div>
          <div class="mb-4">
            <label class="label" for="row-source-type">Source Type</label>
            <select
              id="row-source-type"
              name="row[source_type]"
              class="w-full rounded-md border border-admin-border bg-admin-elevated px-3 py-2 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
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
              class="w-full rounded-md border border-admin-border bg-admin-elevated px-3 py-2 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
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
              class="w-full rounded-md border border-admin-border bg-admin-elevated px-3 py-2 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
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
            <label class="label" for="row-card-variant">Card variant</label>
            <select
              id="row-card-variant"
              name="row[card_variant]"
              class="w-full rounded-md border border-admin-border bg-admin-elevated px-3 py-2 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
              data-test="row-card-variant-select"
            >
              <option
                :for={{label, value} <- card_variant_options(@form[:source_type].value)}
                value={value}
                selected={to_string(@form[:card_variant].value || "") == value}
              >
                {label}
              </option>
            </select>
            <p class="text-xs text-admin-text-muted mt-1">
              Only variants compatible with the selected source type appear. Leave
              as Default to use the system default for that row.
            </p>
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
              class="w-full rounded-md border border-admin-border bg-admin-elevated px-3 py-2 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
            />
          </div>
          <div class="flex justify-end gap-2">
            <button type="button" phx-click="cancel_form" class="inline-flex items-center gap-1.5 rounded-md px-4 py-2 font-ui text-sm font-medium text-admin-text-secondary hover:bg-admin-elevated hover:text-admin-text-primary">Cancel</button>
            <button type="submit" class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-4 py-2 font-ui text-sm font-medium text-admin-accent-text hover:bg-admin-accent-hover">Save</button>
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
      <div class="bg-admin-surface rounded-lg p-6 w-full max-w-2xl shadow-xl" data-test="row-preview">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold">Preview: {@row.title}</h3>
          <button phx-click="close_preview" class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-text-secondary hover:bg-admin-elevated hover:text-admin-text-primary" aria-label="Close">✕</button>
        </div>
        <div class="flex gap-3 overflow-x-auto pb-2">
          <div :for={video <- @videos} class="flex-shrink-0 w-40">
            <div class="w-40 h-24 rounded bg-admin-elevated overflow-hidden">
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
        <div :if={@videos == []} class="py-4 text-center text-admin-text-muted">
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
        <button phx-click="back_from_manage" class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-text-secondary hover:bg-admin-elevated hover:text-admin-text-primary">← Back</button>
        <.header>{@row.title} — Items</.header>
      </div>
      <button
        :if={@can_manage}
        phx-click="open_video_picker"
        class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-3 py-1.5 font-ui text-sm font-medium text-admin-accent-text hover:bg-admin-accent-hover"
        data-test="add-videos-btn"
      >
        Add Videos
      </button>
    </div>

    <div :if={@videos == []} class="py-8 text-center text-admin-text-muted">
      <p>No items in this row yet.</p>
    </div>

    <div :if={@videos != []} class="space-y-2">
      <div
        :for={video <- @videos}
        class="flex items-center gap-3 p-3 bg-admin-bg rounded-lg"
      >
        <div class="flex-1 font-medium truncate">{video.title}</div>
        <div :if={@can_manage} class="flex gap-1">
          <button
            phx-click="remove_video_from_row"
            phx-value-video-id={video.id}
            class="inline-flex items-center gap-1.5 rounded-md border border-error px-2 py-1 font-ui text-xs font-medium text-error hover:bg-error hover:text-admin-accent-text"
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
      <div class="bg-admin-surface rounded-lg p-6 w-full max-w-lg shadow-xl max-h-[80vh] overflow-y-auto">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold">Add Videos</h3>
          <button phx-click="close_video_picker" class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-text-secondary hover:bg-admin-elevated hover:text-admin-text-primary" aria-label="Close">
            ✕
          </button>
        </div>
        <div :if={@available_videos == []} class="py-4 text-center text-admin-text-muted">
          All videos are already in this row.
        </div>
        <div :if={@available_videos != []} class="space-y-2">
          <div
            :for={video <- @available_videos}
            class="flex items-center justify-between p-2 bg-admin-bg rounded"
          >
            <span class="truncate">{video.title}</span>
            <button
              phx-click="add_video_to_row"
              phx-value-video-id={video.id}
              class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-2 py-1 font-ui text-xs font-medium text-admin-accent-text hover:bg-admin-accent-hover"
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
