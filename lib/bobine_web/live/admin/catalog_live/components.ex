defmodule BobineWeb.Admin.CatalogLive.Components do
  @moduledoc """
  Extracted template components for the Catalog LiveView.

  Contains hero editor, rows list, row form, row preview, and row items view
  components along with their helper functions.
  """

  use BobineWeb, :html

  alias Bobine.Catalog.Presets
  alias Bobine.Catalog.Row

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
  def source_type_label(:welcome_text), do: "Welcome text block"
  def source_type_label(other), do: to_string(other)

  @doc """
  Returns card variant options compatible with a row's source_type as
  `{label, value}` tuples suitable for an HTML select. Prepends a blank
  option so operators can clear the variant and fall back to default.
  """
  def card_variant_options(source_type) when is_atom(source_type) and not is_nil(source_type) do
    row_type = Row.compat_row_type(source_type)

    variants = Presets.variants_for_row(row_type)

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
  Returns true when the row's current source_type is `welcome_text`.

  ## Examples

      iex> BobineWeb.Admin.CatalogLive.Components.welcome_text?(:welcome_text)
      true

      iex> BobineWeb.Admin.CatalogLive.Components.welcome_text?("welcome_text")
      true

      iex> BobineWeb.Admin.CatalogLive.Components.welcome_text?(:curated)
      false
  """
  def welcome_text?(value), do: to_string(value) == "welcome_text"

  @doc """
  Normalizes the assorted forms a checkbox value can take across a Phoenix
  LiveView form lifecycle (nil from a fresh struct, "true"/"false" from a
  submitted form, true/false after `to_form/1` coerces types).

      iex> BobineWeb.Admin.CatalogLive.Components.checkbox_checked?(true, default: false)
      true

      iex> BobineWeb.Admin.CatalogLive.Components.checkbox_checked?("true", default: false)
      true

      iex> BobineWeb.Admin.CatalogLive.Components.checkbox_checked?(nil, default: true)
      true

      iex> BobineWeb.Admin.CatalogLive.Components.checkbox_checked?(nil, default: false)
      false
  """
  def checkbox_checked?(value, opts \\ [])
  def checkbox_checked?(true, _opts), do: true
  def checkbox_checked?(false, _opts), do: false
  def checkbox_checked?("true", _opts), do: true
  def checkbox_checked?("false", _opts), do: false
  def checkbox_checked?(nil, opts), do: Keyword.get(opts, :default, false)
  def checkbox_checked?(_, opts), do: Keyword.get(opts, :default, false)

  @doc """
  Pulls a string value from the row form's `filter_config` map for the
  welcome-text editor. Returns an empty string when the key is missing.

  ## Examples

      iex> import Phoenix.Component, only: [to_form: 1]
      iex> form = to_form(%{"filter_config" => %{"headline" => "Hello"}}, as: :row)
      iex> BobineWeb.Admin.CatalogLive.Components.welcome_config_value(form, "headline")
      "Hello"

      iex> import Phoenix.Component, only: [to_form: 1]
      iex> form = to_form(%{"filter_config" => %{}}, as: :row)
      iex> BobineWeb.Admin.CatalogLive.Components.welcome_config_value(form, "headline")
      ""
  """
  def welcome_config_value(form, key) do
    case form[:filter_config].value do
      %{} = map -> to_string(Map.get(map, key) || Map.get(map, String.to_atom(key)) || "")
      _ -> ""
    end
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
  attr :hero_expanded_slide, :string, default: nil
  attr :hero_picker_tab, :atom, default: :existing
  attr :hero_upload_file, :map, default: nil
  attr :hero_uploading, :boolean, default: false
  attr :hero_upload_percent, :integer, default: 0
  attr :hero_replacing_slide_id, :string, default: nil

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
              class={"rounded-full px-2 py-0.5 font-ui text-xs #{if @hero_row.visible, do: "border border-success/40 bg-success/10 text-success", else: "bg-admin-card text-admin-muted"}"}
            >
              {if @hero_row.visible, do: "Visible", else: "Hidden"}
            </button>
          </div>
        <% end %>
      </div>

      <div :if={!@hero_collapsed} id="hero-editor-body">
        <%= if is_nil(@hero_row) do %>
          <div class="py-8 text-center bg-admin-bg rounded-lg">
            <p class="text-admin-muted mb-4">
              Create a hero carousel to feature up to 4 items at the top of your homepage.
            </p>
            <BobineWeb.Components.AdminUI.admin_button
              :if={@can_manage}
              phx-click="create_hero"
              data-test="create-hero-btn"
            >
              Create hero carousel
            </BobineWeb.Components.AdminUI.admin_button>
          </div>
        <% else %>
          <div :if={@can_manage} class="flex items-center gap-3 mb-4 p-3 bg-admin-bg rounded-lg">
            <label for="hero-auto-advance" class="font-ui text-sm font-medium text-admin-fg">
              Auto-rotate
            </label>
            <form phx-submit="save_hero_auto_advance" class="flex items-center gap-2">
              <select
                id="hero-auto-advance"
                name="auto_advance_ms"
                class="w-auto rounded-md border border-admin-border bg-admin-card px-2 py-1 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                data-test="hero-auto-advance-select"
              >
                <option value="0" selected={hero_auto_advance_ms(@hero_row) == 0}>Off</option>
                <option value="5000" selected={hero_auto_advance_ms(@hero_row) == 5000}>5s</option>
                <option value="8000" selected={hero_auto_advance_ms(@hero_row) == 8000}>8s</option>
                <option value="10000" selected={hero_auto_advance_ms(@hero_row) == 10_000}>
                  10s
                </option>
                <option value="15000" selected={hero_auto_advance_ms(@hero_row) == 15_000}>
                  15s
                </option>
              </select>
              <BobineWeb.Components.AdminUI.admin_button
                type="submit"
                size={:sm}
                phx-disable-with="Saving..."
                data-test="hero-auto-advance-save-btn"
              >
                Save
              </BobineWeb.Components.AdminUI.admin_button>
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

          <div class="space-y-2">
            <div
              :for={slide <- @hero_slides}
              class="rounded-lg border border-admin-border overflow-hidden"
              data-test={"hero-slide-editor-#{slide.position}"}
            >
              <%!-- Accordion header — always visible --%>
              <button
                type="button"
                phx-click="expand_hero_slide"
                phx-value-slide-id={slide.id}
                class="flex w-full items-center gap-3 bg-admin-bg px-4 py-3 text-left transition-colors hover:bg-admin-card"
                aria-expanded={to_string(@hero_expanded_slide == slide.id)}
              >
                <span class="rounded bg-admin-card px-2 py-0.5 font-mono text-xs text-admin-muted">
                  {slide.position + 1}
                </span>
                <span class="min-w-0 flex-1 truncate font-ui text-sm font-medium text-admin-fg">
                  {slide.headline || slide.video_title}
                </span>
                <span
                  :if={@hero_save_status[slide.id] == :ok}
                  class="text-xs text-success"
                  data-test={"hero-slide-save-success-#{slide.position}"}
                  role="status"
                >
                  Saved
                </span>
                <span
                  :if={@hero_save_status[slide.id] == :error}
                  class="text-xs text-error"
                  data-test={"hero-slide-save-error-#{slide.position}"}
                  role="alert"
                >
                  Error
                </span>
                <.icon
                  name={
                    if @hero_expanded_slide == slide.id,
                      do: "hero-chevron-up",
                      else: "hero-chevron-down"
                  }
                  class="size-4 shrink-0 text-admin-muted"
                />
              </button>

              <%!-- Accordion body — only when expanded --%>
              <div
                :if={@hero_expanded_slide == slide.id}
                class="border-t border-admin-border bg-admin-card px-4 py-4"
              >
                <div :if={@can_manage} class="flex items-center gap-1 mb-4">
                  <BobineWeb.Components.AdminUI.admin_button
                    variant={:secondary}
                    size={:sm}
                    phx-click="replace_hero_video"
                    phx-value-slide-id={slide.id}
                    data-test={"hero-replace-video-#{slide.position}"}
                  >
                    <.icon name="hero-arrow-path" class="size-4" /> Replace video
                  </BobineWeb.Components.AdminUI.admin_button>
                  <BobineWeb.Components.AdminUI.admin_button
                    variant={:ghost}
                    size={:sm}
                    phx-click="move_hero_slide_up"
                    phx-value-slide-id={slide.id}
                  >
                    <.icon name="hero-arrow-up" class="size-4" /> Up
                  </BobineWeb.Components.AdminUI.admin_button>
                  <BobineWeb.Components.AdminUI.admin_button
                    variant={:ghost}
                    size={:sm}
                    phx-click="move_hero_slide_down"
                    phx-value-slide-id={slide.id}
                  >
                    <.icon name="hero-arrow-down" class="size-4" /> Down
                  </BobineWeb.Components.AdminUI.admin_button>
                  <span class="flex-1" />
                  <BobineWeb.Components.AdminUI.admin_button
                    variant={:danger}
                    size={:sm}
                    phx-click="remove_hero_slide"
                    phx-value-slide-id={slide.id}
                    data-test={"hero-remove-slide-#{slide.position}"}
                  >
                    Remove
                  </BobineWeb.Components.AdminUI.admin_button>
                </div>

                <form
                  phx-submit="save_hero_slide"
                  phx-change="save_hero_slide"
                  phx-debounce="800"
                  class="space-y-3"
                >
                  <input type="hidden" name="slide-id" value={slide.id} />

                  <div>
                    <div class="flex items-center justify-between mb-1">
                      <label class="font-ui text-xs font-medium text-admin-muted">
                        Headline
                      </label>
                      <.slide_show_toggle
                        name="show_headline"
                        checked={slide.show_headline}
                        position={slide.position}
                      />
                    </div>
                    <input
                      type="text"
                      name="headline"
                      value={slide.headline}
                      placeholder={slide.video_title}
                      class="w-full rounded-md border border-admin-border bg-admin-bg px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                      data-test={"hero-headline-input-#{slide.position}"}
                    />
                  </div>

                  <div class="grid grid-cols-2 gap-3">
                    <div>
                      <div class="flex items-center justify-between mb-1">
                        <label class="font-ui text-xs font-medium text-admin-muted">
                          Subheadline
                        </label>
                        <.slide_show_toggle
                          name="show_subheadline"
                          checked={slide.show_subheadline}
                          position={slide.position}
                        />
                      </div>
                      <input
                        type="text"
                        name="subheadline"
                        value={slide.subheadline}
                        placeholder="optional"
                        class="w-full rounded-md border border-admin-border bg-admin-bg px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                        data-test={"hero-subheadline-input-#{slide.position}"}
                      />
                    </div>
                    <div>
                      <div class="flex items-center justify-between mb-1">
                        <label class="font-ui text-xs font-medium text-admin-muted">
                          Brand Tag
                        </label>
                        <.slide_show_toggle
                          name="show_brand_tag"
                          checked={slide.show_brand_tag}
                          position={slide.position}
                        />
                      </div>
                      <input
                        type="text"
                        name="brand_tag"
                        value={slide.brand_tag}
                        placeholder="optional"
                        class="w-full rounded-md border border-admin-border bg-admin-bg px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                        data-test={"hero-brand-tag-input-#{slide.position}"}
                      />
                    </div>
                  </div>

                  <div>
                    <div class="flex items-center justify-between mb-1">
                      <label class="font-ui text-xs font-medium text-admin-muted">
                        Description
                      </label>
                      <.slide_show_toggle
                        name="show_description"
                        checked={slide.show_description}
                        position={slide.position}
                      />
                    </div>
                    <textarea
                      name="description"
                      placeholder={slide.video_description || "optional"}
                      rows="2"
                      class="w-full rounded-md border border-admin-border bg-admin-bg px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                      data-test={"hero-description-input-#{slide.position}"}
                    >{slide.description}</textarea>
                  </div>

                  <div class="grid grid-cols-2 gap-3">
                    <div>
                      <div class="flex items-center justify-between mb-1">
                        <label class="font-ui text-xs font-medium text-admin-muted">
                          Primary CTA
                        </label>
                        <.slide_show_toggle
                          name="show_primary_cta"
                          checked={slide.show_primary_cta}
                          position={slide.position}
                        />
                      </div>
                      <input
                        type="text"
                        name="primary_cta_label"
                        value={slide.primary_cta_label}
                        placeholder="Watch now"
                        class="w-full rounded-md border border-admin-border bg-admin-bg px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                        data-test={"hero-primary-cta-input-#{slide.position}"}
                      />
                    </div>
                    <div>
                      <div class="flex items-center justify-between mb-1">
                        <label class="font-ui text-xs font-medium text-admin-muted">
                          Secondary CTA
                        </label>
                        <.slide_show_toggle
                          name="show_secondary_cta"
                          checked={slide.show_secondary_cta}
                          position={slide.position}
                        />
                      </div>
                      <input
                        type="text"
                        name="secondary_cta_label"
                        value={slide.secondary_cta_label}
                        placeholder="More info"
                        class="w-full rounded-md border border-admin-border bg-admin-bg px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                        data-test={"hero-secondary-cta-input-#{slide.position}"}
                      />
                    </div>
                  </div>

                  <div>
                    <label class="block font-ui text-xs font-medium text-admin-muted mb-1">
                      Custom Background URL
                    </label>
                    <input
                      type="text"
                      name="background_image_url"
                      value={slide.background_image_url}
                      placeholder="Uses video thumbnail if empty"
                      class="w-full rounded-md border border-admin-border bg-admin-bg px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                      data-test={"hero-bg-url-input-#{slide.position}"}
                    />
                  </div>

                  <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <div>
                      <label class="block font-ui text-xs font-medium text-admin-muted mb-1">
                        Title Logo URL
                      </label>
                      <input
                        type="text"
                        name="title_logo_url"
                        value={slide.title_logo_url}
                        placeholder="Replaces the text headline when set"
                        class="w-full rounded-md border border-admin-border bg-admin-bg px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                        data-test={"hero-title-logo-url-input-#{slide.position}"}
                      />
                      <img
                        :if={slide.title_logo_url}
                        src={slide.title_logo_url}
                        alt=""
                        class="mt-2 max-h-16 w-auto rounded border border-admin-border bg-admin-card p-2 object-contain"
                        data-test={"hero-title-logo-preview-#{slide.position}"}
                      />
                    </div>
                    <div>
                      <label class="block font-ui text-xs font-medium text-admin-muted mb-1">
                        Channel / Studio Logo URL
                      </label>
                      <input
                        type="text"
                        name="channel_logo_url"
                        value={slide.channel_logo_url}
                        placeholder="Optional network or studio mark"
                        class="w-full rounded-md border border-admin-border bg-admin-bg px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                        data-test={"hero-channel-logo-url-input-#{slide.position}"}
                      />
                      <img
                        :if={slide.channel_logo_url}
                        src={slide.channel_logo_url}
                        alt=""
                        class="mt-2 max-h-10 w-auto rounded border border-admin-border bg-admin-card p-2 object-contain"
                        data-test={"hero-channel-logo-preview-#{slide.position}"}
                      />
                    </div>
                  </div>

                  <div class="flex justify-end">
                    <BobineWeb.Components.AdminUI.admin_button
                      :if={@can_manage}
                      type="submit"
                      size={:sm}
                      phx-disable-with="Saving..."
                      data-test={"hero-slide-save-btn-#{slide.position}"}
                    >
                      Save
                    </BobineWeb.Components.AdminUI.admin_button>
                  </div>
                </form>
              </div>
            </div>

            <div :if={@can_manage && length(@hero_slides) < 4}>
              <button
                phx-click="open_hero_video_picker"
                class="flex w-full items-center justify-center gap-1.5 rounded-lg border border-dashed border-admin-border px-3 py-3 font-ui text-sm text-admin-muted transition-colors hover:border-admin-accent hover:text-admin-accent"
                data-test="hero-add-slide-btn"
              >
                + Add slide ({length(@hero_slides)}/4)
              </button>
            </div>

            <p
              :if={@can_manage && length(@hero_slides) >= 4}
              class="text-center text-sm text-admin-muted"
            >
              Maximum of 4 slides reached.
            </p>
          </div>

          <BobineWeb.Components.AdminUI.admin_sheet
            id="hero-video-picker"
            open={@show_hero_video_picker}
            title={if @hero_replacing_slide_id, do: "Replace Slide Video", else: "Add Hero Slide"}
            subtitle="Pick an existing video or upload a new one to Mux."
            on_close="close_hero_video_picker"
          >
            <div class="mb-4 flex gap-1 rounded-lg bg-admin-bg p-1" role="tablist">
              <button
                type="button"
                phx-click="hero_picker_tab"
                phx-value-tab="existing"
                role="tab"
                aria-selected={to_string(@hero_picker_tab == :existing)}
                class={[
                  "flex-1 rounded-md px-3 py-1.5 font-ui text-sm font-medium transition-colors",
                  if(@hero_picker_tab == :existing,
                    do: "bg-admin-card text-admin-fg shadow-sm",
                    else: "text-admin-muted hover:text-admin-fg"
                  )
                ]}
                data-test="hero-picker-tab-existing"
              >
                From Content
              </button>
              <button
                type="button"
                phx-click="hero_picker_tab"
                phx-value-tab="upload"
                role="tab"
                aria-selected={to_string(@hero_picker_tab == :upload)}
                class={[
                  "flex-1 rounded-md px-3 py-1.5 font-ui text-sm font-medium transition-colors",
                  if(@hero_picker_tab == :upload,
                    do: "bg-admin-card text-admin-fg shadow-sm",
                    else: "text-admin-muted hover:text-admin-fg"
                  )
                ]}
                data-test="hero-picker-tab-upload"
              >
                Upload new
              </button>
            </div>

            <div :if={@hero_picker_tab == :existing}>
              <div :if={@hero_available_videos == []} class="py-8 text-center text-admin-muted">
                No available videos. Switch to <strong>Upload new</strong> to add one.
              </div>
              <div :if={@hero_available_videos != []} class="space-y-2">
                <div
                  :for={video <- @hero_available_videos}
                  class="flex items-center justify-between rounded-lg border border-admin-border bg-admin-bg px-3 py-2"
                >
                  <span
                    class="min-w-0 flex-1 truncate font-body text-sm text-admin-fg"
                    data-test={"hero-video-select-#{video.id}"}
                  >
                    {video.title}
                  </span>
                  <BobineWeb.Components.AdminUI.admin_button
                    size={:sm}
                    phx-click="add_hero_slide"
                    phx-value-video-id={video.id}
                  >
                    Select
                  </BobineWeb.Components.AdminUI.admin_button>
                </div>
              </div>
            </div>

            <div :if={@hero_picker_tab == :upload}>
              <div :if={@hero_uploading} class="space-y-2" data-test="hero-upload-progress">
                <p class="font-ui text-sm text-admin-fg">
                  Uploading… {@hero_upload_percent}%
                </p>
                <div class="h-2 w-full rounded-full bg-admin-bg">
                  <div
                    class="h-2 rounded-full bg-admin-accent transition-[width] duration-200"
                    style={"width: #{@hero_upload_percent}%"}
                  >
                  </div>
                </div>
                <p class="font-body text-xs text-admin-muted">
                  Video bytes go direct to Mux — don't close this sheet until the upload finishes.
                </p>
              </div>

              <form
                :if={!@hero_uploading}
                phx-submit="submit_hero_upload"
                class="space-y-4"
              >
                <div>
                  <label class="block font-ui text-xs font-medium text-admin-muted mb-1">
                    Video file
                  </label>
                  <input
                    type="file"
                    accept="video/*"
                    data-test="upload-file"
                    id="hero-upload-file"
                    class="block w-full rounded-md border border-admin-border bg-admin-bg px-3 py-2 font-body text-sm text-admin-fg file:mr-3 file:rounded file:border-0 file:bg-admin-accent file:px-3 file:py-1 file:font-ui file:text-sm file:font-medium file:text-admin-on-accent hover:file:brightness-110"
                  />
                </div>

                <div :if={@hero_upload_file}>
                  <label class="block font-ui text-xs font-medium text-admin-muted mb-1">
                    Title
                  </label>
                  <input
                    type="text"
                    name="title"
                    value={@hero_upload_file.title}
                    placeholder={@hero_upload_file.name}
                    class="w-full rounded-md border border-admin-border bg-admin-bg px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                    data-test="hero-upload-title"
                  />
                </div>

                <div
                  :if={@hero_upload_file == nil}
                  class="py-4 text-center text-admin-muted font-body text-sm"
                >
                  Choose a video file to continue.
                </div>

                <div :if={@hero_upload_file} class="flex justify-end">
                  <BobineWeb.Components.AdminUI.admin_button
                    type="submit"
                    size={:sm}
                    data-test="hero-upload-submit"
                    phx-disable-with="Starting…"
                  >
                    Upload & add slide
                  </BobineWeb.Components.AdminUI.admin_button>
                </div>
              </form>
            </div>
          </BobineWeb.Components.AdminUI.admin_sheet>
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
        class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-4 py-2 font-ui text-sm font-medium text-admin-on-accent hover:brightness-110"
        data-test="new-row-btn"
      >
        New Row
      </button>
    </div>

    <div
      :if={@rows == []}
      class="py-12 text-center text-admin-muted"
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
              <span class="rounded-full border border-admin-border px-2 py-0.5 font-ui text-xs text-admin-muted">
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
                  class="w-auto rounded-md border border-admin-border bg-admin-card px-2 py-1 font-body text-xs text-admin-fg focus:border-admin-accent focus:outline-none"
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
                class="text-xs text-admin-muted"
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
                class={"rounded-full px-2 py-0.5 font-ui text-xs #{if row.visible, do: "border border-success/40 bg-success/10 text-success", else: "bg-admin-card text-admin-muted"}"}
              >
                {if row.visible, do: "Visible", else: "Hidden"}
              </button>
            </td>
            <td class="flex gap-1">
              <button
                :if={@can_manage}
                phx-click="move_up"
                phx-value-id={row.id}
                class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
                aria-label="Move row up"
              >
                ↑
              </button>
              <button
                :if={@can_manage}
                phx-click="move_down"
                phx-value-id={row.id}
                class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
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
                  class="inline-flex items-center gap-1.5 rounded-md border border-admin-border px-2 py-1 font-ui text-xs font-medium text-admin-fg hover:border-admin-border"
                  data-test="row-preview"
                >
                  Preview
                </button>
                <button
                  :if={row.source_type == :curated}
                  phx-click="manage_items"
                  phx-value-id={row.id}
                  class="inline-flex items-center gap-1.5 rounded-md border border-admin-border px-2 py-1 font-ui text-xs font-medium text-admin-fg hover:border-admin-border"
                >
                  Items
                </button>
                <button
                  phx-click="edit_row"
                  phx-value-id={row.id}
                  class="inline-flex items-center gap-1.5 rounded-md border border-admin-border px-2 py-1 font-ui text-xs font-medium text-admin-fg hover:border-admin-border"
                >
                  Edit
                </button>
                <button
                  phx-click="delete_row"
                  phx-value-id={row.id}
                  data-confirm="Are you sure?"
                  class="inline-flex items-center gap-1.5 rounded-md border border-error px-2 py-1 font-ui text-xs font-medium text-error hover:bg-error hover:text-admin-on-accent"
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
      <div class="bg-admin-card rounded-lg p-6 w-full max-w-md shadow-xl">
        <h3 class="text-lg font-semibold mb-4">
          {if @editing, do: "Edit Row", else: "New Row"}
        </h3>
        <.form
          for={@form}
          phx-submit="save_row"
          phx-change="change_row"
          data-test="row-form"
        >
          <div class="mb-4">
            <label class="label" for="row-title">Title</label>
            <input
              type="text"
              id="row-title"
              name="row[title]"
              value={@form[:title].value}
              required
              class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
              data-test="row-title-input"
            />
          </div>
          <div class="mb-4">
            <label class="label" for="row-source-type">Source Type</label>
            <select
              id="row-source-type"
              name="row[source_type]"
              class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
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
              class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
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
              class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
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
          <div
            :if={show_source_select?(@form[:source_type].value, :welcome_text)}
            data-test="welcome-text-fields"
          >
            <div class="mb-4">
              <label class="label" for="row-welcome-eyebrow">Eyebrow</label>
              <input
                type="text"
                id="row-welcome-eyebrow"
                name="row[filter_config][eyebrow]"
                value={welcome_config_value(@form, "eyebrow")}
                placeholder="Welcome to the show"
                class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                data-test="row-welcome-eyebrow"
              />
            </div>
            <div class="mb-4">
              <label class="label" for="row-welcome-headline">Headline</label>
              <input
                type="text"
                id="row-welcome-headline"
                name="row[filter_config][headline]"
                value={welcome_config_value(@form, "headline")}
                placeholder="Defaults to the row title when blank"
                class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                data-test="row-welcome-headline"
              />
            </div>
            <div class="mb-4">
              <label class="label" for="row-welcome-body">Body</label>
              <textarea
                id="row-welcome-body"
                name="row[filter_config][body]"
                rows="3"
                class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                data-test="row-welcome-body"
              >{welcome_config_value(@form, "body")}</textarea>
            </div>
            <div class="mb-4">
              <label class="label" for="row-welcome-cta-label">CTA label</label>
              <input
                type="text"
                id="row-welcome-cta-label"
                name="row[filter_config][cta_label]"
                value={welcome_config_value(@form, "cta_label")}
                placeholder="Browse the catalog"
                class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                data-test="row-welcome-cta-label"
              />
            </div>
            <div class="mb-4">
              <label class="label" for="row-welcome-cta-href">CTA link</label>
              <input
                type="text"
                id="row-welcome-cta-href"
                name="row[filter_config][cta_href]"
                value={welcome_config_value(@form, "cta_href")}
                placeholder="/browse"
                class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                data-test="row-welcome-cta-href"
              />
            </div>
            <p class="mb-4 text-xs text-admin-muted">
              CTA button is only rendered when both label and link are filled in.
            </p>
          </div>
          <div
            :if={not welcome_text?(@form[:source_type].value)}
            class="mb-4"
          >
            <label class="label" for="row-card-variant">Card variant</label>
            <select
              id="row-card-variant"
              name="row[card_variant]"
              class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
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
            <p class="text-xs text-admin-muted mt-1">
              Only variants compatible with the selected source type appear. Leave
              as Default to use the system default for that row.
            </p>
          </div>
          <div
            :if={not welcome_text?(@form[:source_type].value)}
            class="mb-4"
          >
            <label class="label" for="row-max-items">Max Items</label>
            <input
              type="number"
              id="row-max-items"
              name="row[max_items]"
              value={@form[:max_items].value || 20}
              min="5"
              max="50"
              class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
            />
          </div>

          <div
            :if={not welcome_text?(@form[:source_type].value)}
            class="mb-4 space-y-2 rounded-md border border-admin-border bg-admin-bg/40 p-3"
          >
            <%!-- Phoenix form checkboxes ship a hidden "false" field that
                 the browser submits when the box is unchecked. That keeps
                 the params explicit and avoids the classic "checkbox missing
                 from params" toggle bug. --%>
            <label class="flex items-start gap-2">
              <input type="hidden" name="row[show_details]" value="false" />
              <input
                type="checkbox"
                name="row[show_details]"
                value="true"
                checked={checkbox_checked?(@form[:show_details].value, default: true)}
                class="mt-0.5 h-4 w-4 rounded border-admin-border"
                data-test="row-show-details-input"
              />
              <span>
                <span class="block font-ui text-sm font-medium text-admin-fg">
                  Show details below card
                </span>
                <span class="block font-body text-xs text-admin-muted">
                  Uncheck to hide the title and metadata beneath each thumbnail.
                </span>
              </span>
            </label>

            <label
              :if={not checkbox_checked?(@form[:show_details].value, default: true)}
              class="flex items-start gap-2"
              data-test="row-title-overlay-wrapper"
            >
              <input type="hidden" name="row[title_overlay]" value="false" />
              <input
                type="checkbox"
                name="row[title_overlay]"
                value="true"
                checked={checkbox_checked?(@form[:title_overlay].value, default: false)}
                class="mt-0.5 h-4 w-4 rounded border-admin-border"
                data-test="row-title-overlay-input"
              />
              <span>
                <span class="block font-ui text-sm font-medium text-admin-fg">
                  Overlay title on thumbnail
                </span>
                <span class="block font-body text-xs text-admin-muted">
                  When details are hidden, show the title on top of the image.
                </span>
              </span>
            </label>
          </div>
          <div class="flex justify-end gap-2">
            <button
              type="button"
              phx-click="cancel_form"
              class="inline-flex items-center gap-1.5 rounded-md px-4 py-2 font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-4 py-2 font-ui text-sm font-medium text-admin-on-accent hover:brightness-110"
            >
              Save
            </button>
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
      <div class="bg-admin-card rounded-lg p-6 w-full max-w-2xl shadow-xl" data-test="row-preview">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold">Preview: {@row.title}</h3>
          <button
            phx-click="close_preview"
            class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
            aria-label="Close"
          >
            ✕
          </button>
        </div>
        <div class="flex gap-3 overflow-x-auto pb-2">
          <div :for={video <- @videos} class="flex-shrink-0 w-40">
            <div class="w-40 h-24 rounded bg-admin-card overflow-hidden">
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
        <div :if={@videos == []} class="py-4 text-center text-admin-muted">
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
        <button
          phx-click="back_from_manage"
          class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
        >
          ← Back
        </button>
        <.header>{@row.title} — Items</.header>
      </div>
      <button
        :if={@can_manage}
        phx-click="open_video_picker"
        class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-3 py-1.5 font-ui text-sm font-medium text-admin-on-accent hover:brightness-110"
        data-test="add-videos-btn"
      >
        Add Videos
      </button>
    </div>

    <div :if={@videos == []} class="py-8 text-center text-admin-muted">
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
            class="inline-flex items-center gap-1.5 rounded-md border border-error px-2 py-1 font-ui text-xs font-medium text-error hover:bg-error hover:text-admin-on-accent"
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
      <div class="bg-admin-card rounded-lg p-6 w-full max-w-lg shadow-xl max-h-[80vh] overflow-y-auto">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold">Add Videos</h3>
          <button
            phx-click="close_video_picker"
            class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
            aria-label="Close"
          >
            ✕
          </button>
        </div>
        <div :if={@available_videos == []} class="py-4 text-center text-admin-muted">
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
              class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-2 py-1 font-ui text-xs font-medium text-admin-on-accent hover:brightness-110"
            >
              Add
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :checked, :boolean, required: true
  attr :position, :integer, required: true

  defp slide_show_toggle(assigns) do
    ~H"""
    <label class="flex items-center gap-1.5 font-ui text-xs text-admin-muted cursor-pointer">
      <input type="hidden" name={@name} value="false" />
      <input
        type="checkbox"
        name={@name}
        value="true"
        checked={@checked}
        class="size-3.5 rounded border-admin-border bg-admin-bg text-admin-accent focus:ring-admin-accent"
        data-test={"hero-#{@name}-toggle-#{@position}"}
      />
      <span>Show</span>
    </label>
    """
  end
end
