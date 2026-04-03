defmodule BobineWeb.Admin.CatalogLive do
  use BobineWeb, :live_view

  alias Bobine.Accounts
  alias Bobine.Catalog
  alias Bobine.Content
  alias Bobine.Events

  @source_types [
    {"Curated", "curated"},
    {"Collection", "collection"},
    {"Tag", "tag"},
    {"Recent", "recent"},
    {"Popular", "popular"},
    {"Continue Watching", "continue_watching"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Events.subscribe(org.id)
    end

    can_manage = Accounts.can_manage_content?(scope)

    {:ok,
     socket
     |> assign(:page_title, "Catalog")
     |> assign(:can_manage, can_manage)
     |> assign(:show_form, false)
     |> assign(:editing_row, nil)
     |> assign(:form, nil)
     |> assign(:source_types, @source_types)
     |> assign(:collections, [])
     |> assign(:tags, [])
     |> assign(:preview_videos, [])
     |> assign(:selected_row, nil)
     |> assign(:show_video_picker, false)
     |> assign(:available_videos, [])
     |> assign(:row_videos, [])
     # Hero editor state
     |> assign(:hero_row, nil)
     |> assign(:hero_slides, [])
     |> assign(:hero_slide_forms, %{})
     |> assign(:show_hero_video_picker, false)
     |> assign(:hero_available_videos, [])
     |> assign(:hero_save_status, %{})
     |> assign(:hero_collapsed, false)
     |> load_rows()
     |> load_hero_row()}
  end

  # ── Row events ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("new_row", _params, socket) do
    form =
      Catalog.change_row(%Bobine.Catalog.Row{})
      |> to_form()

    org = socket.assigns.organization
    %{results: collections} = Content.list_collections(org)
    %{results: tags} = Content.list_tags(org)

    {:noreply,
     assign(socket,
       show_form: true,
       editing_row: nil,
       form: form,
       collections: collections,
       tags: tags
     )}
  end

  @impl true
  def handle_event("edit_row", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Catalog.get_row(org, id) do
      {:ok, row} ->
        form = Catalog.change_row(row) |> to_form()
        %{results: collections} = Content.list_collections(org)
        %{results: tags} = Content.list_tags(org)

        {:noreply,
         assign(socket,
           show_form: true,
           editing_row: row,
           form: form,
           collections: collections,
           tags: tags
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Row not found.")}
    end
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, show_form: false, editing_row: nil, form: nil, preview_videos: [])}
  end

  @impl true
  def handle_event("save_row", %{"row" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      case socket.assigns.editing_row do
        nil -> Catalog.create_row(scope, params)
        row -> Catalog.update_row(scope, row, params)
      end

    case result do
      {:ok, _row} ->
        {:noreply,
         socket
         |> assign(show_form: false, editing_row: nil, form: nil, preview_videos: [])
         |> put_flash(:info, "Row saved.")
         |> load_rows()}

      {:error, :validation, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete_row", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Catalog.get_row(org, id) do
      {:ok, row} ->
        {:ok, _} = Catalog.delete_row(scope, row)

        {:noreply,
         socket
         |> put_flash(:info, "Row deleted.")
         |> load_rows()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Row not found.")}
    end
  end

  @impl true
  def handle_event("toggle_visibility", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Catalog.get_row(org, id) do
      {:ok, row} ->
        {:ok, _} = Catalog.update_row(scope, row, %{visible: !row.visible})

        {:noreply,
         socket
         |> load_rows()
         |> load_hero_row()}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("preview_row", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Catalog.get_row(org, id) do
      {:ok, row} ->
        %{results: videos} = Catalog.resolve_row_content(org, row, per_page: 5)
        {:noreply, assign(socket, selected_row: row, preview_videos: videos)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Row not found.")}
    end
  end

  @impl true
  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, selected_row: nil, preview_videos: [])}
  end

  @impl true
  def handle_event("move_up", %{"id" => id}, socket) do
    reorder_row(socket, id, :up)
  end

  @impl true
  def handle_event("move_down", %{"id" => id}, socket) do
    reorder_row(socket, id, :down)
  end

  # ── Curated row item events ────────────────────────────────────────────

  @impl true
  def handle_event("manage_items", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Catalog.get_row(org, id) do
      {:ok, row} ->
        %{results: videos} = Catalog.list_row_items(org, row)

        {:noreply,
         assign(socket,
           selected_row: row,
           row_videos: videos,
           preview_videos: []
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Row not found.")}
    end
  end

  @impl true
  def handle_event("back_from_manage", _params, socket) do
    {:noreply,
     assign(socket,
       selected_row: nil,
       row_videos: [],
       show_video_picker: false,
       available_videos: []
     )}
  end

  @impl true
  def handle_event("open_video_picker", _params, socket) do
    org = socket.assigns.organization
    %{results: all_videos} = Content.list_videos(org, per_page: 100)
    row_video_ids = MapSet.new(socket.assigns.row_videos, & &1.id)
    available = Enum.reject(all_videos, &MapSet.member?(row_video_ids, &1.id))

    {:noreply, assign(socket, show_video_picker: true, available_videos: available)}
  end

  @impl true
  def handle_event("close_video_picker", _params, socket) do
    {:noreply, assign(socket, show_video_picker: false, available_videos: [])}
  end

  @impl true
  def handle_event("add_video_to_row", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    row = socket.assigns.selected_row

    case Content.get_video(org, video_id) do
      {:ok, video} ->
        case Catalog.add_item_to_row(scope, row, video) do
          {:ok, _} ->
            %{results: videos} = Catalog.list_row_items(org, row)

            {:noreply,
             assign(socket,
               row_videos: videos,
               show_video_picker: false,
               available_videos: []
             )}

          _ ->
            {:noreply, put_flash(socket, :error, "Failed to add video.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Video not found.")}
    end
  end

  @impl true
  def handle_event("remove_video_from_row", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    row = socket.assigns.selected_row

    case Content.get_video(org, video_id) do
      {:ok, video} ->
        :ok = Catalog.remove_item_from_row(scope, row, video)
        %{results: videos} = Catalog.list_row_items(org, row)
        {:noreply, assign(socket, row_videos: videos)}

      _ ->
        {:noreply, put_flash(socket, :error, "Video not found.")}
    end
  end

  # ── Hero events ────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_hero_collapsed", _params, socket) do
    {:noreply, update(socket, :hero_collapsed, &(!&1))}
  end

  @impl true
  def handle_event("create_hero", _params, socket) do
    scope = socket.assigns.current_scope

    case Catalog.create_hero_row(scope, %{}) do
      {:ok, _row} ->
        {:noreply,
         socket
         |> put_flash(:info, "Hero carousel created.")
         |> load_rows()
         |> load_hero_row()}

      {:error, :already_exists} ->
        {:noreply,
         socket
         |> put_flash(:error, "Hero carousel already exists.")
         |> load_hero_row()}
    end
  end

  @impl true
  def handle_event("toggle_hero_visibility", _params, socket) do
    scope = socket.assigns.current_scope
    hero_row = socket.assigns.hero_row

    if hero_row do
      {:ok, _} = Catalog.update_row(scope, hero_row, %{visible: !hero_row.visible})

      {:noreply,
       socket
       |> load_rows()
       |> load_hero_row()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_hero_video_picker", _params, socket) do
    org = socket.assigns.organization
    %{results: all_videos} = Content.list_videos(org, per_page: 100)
    hero_video_ids = MapSet.new(socket.assigns.hero_slides, & &1.video_id)
    available = Enum.reject(all_videos, &MapSet.member?(hero_video_ids, &1.id))

    {:noreply, assign(socket, show_hero_video_picker: true, hero_available_videos: available)}
  end

  @impl true
  def handle_event("close_hero_video_picker", _params, socket) do
    {:noreply, assign(socket, show_hero_video_picker: false, hero_available_videos: [])}
  end

  @impl true
  def handle_event("add_hero_slide", %{"video-id" => video_id}, socket) do
    scope = socket.assigns.current_scope
    hero_row = socket.assigns.hero_row

    case Catalog.create_hero_slide(scope, hero_row, %{video_id: video_id}) do
      {:ok, _slide} ->
        {:noreply,
         socket
         |> assign(show_hero_video_picker: false, hero_available_videos: [])
         |> load_hero_slides()}

      {:error, :hero_limit_reached, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Maximum of 4 hero slides reached.")
         |> assign(show_hero_video_picker: false, hero_available_videos: [])}

      {:error, :validation, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add hero slide.")}
    end
  end

  @impl true
  def handle_event("save_hero_slide", %{"slide-id" => slide_id} = params, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Catalog.get_hero_slide(org, slide_id) do
      {:ok, slide} ->
        attrs = %{
          headline: blank_to_nil(params["headline"]),
          subheadline: blank_to_nil(params["subheadline"]),
          brand_tag: blank_to_nil(params["brand_tag"]),
          description: blank_to_nil(params["description"]),
          primary_cta_label: blank_to_nil(params["primary_cta_label"]),
          secondary_cta_label: blank_to_nil(params["secondary_cta_label"]),
          background_image_url: blank_to_nil(params["background_image_url"])
        }

        case Catalog.update_hero_slide(scope, slide, attrs) do
          {:ok, _} ->
            Process.send_after(self(), {:clear_hero_save_status, slide_id}, 3_000)

            {:noreply,
             socket
             |> put_flash(:info, "Slide updated.")
             |> update(:hero_save_status, &Map.put(&1, slide_id, :ok))
             |> load_hero_slides()}

          {:error, :validation, _changeset} ->
            Process.send_after(self(), {:clear_hero_save_status, slide_id}, 5_000)

            {:noreply,
             socket
             |> put_flash(:error, "Failed to update slide.")
             |> update(:hero_save_status, &Map.put(&1, slide_id, :error))}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Slide not found.")}
    end
  end

  @impl true
  def handle_event("remove_hero_slide", %{"slide-id" => slide_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Catalog.get_hero_slide(org, slide_id) do
      {:ok, slide} ->
        {:ok, _} = Catalog.delete_hero_slide(scope, slide)
        {:noreply, load_hero_slides(socket)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Slide not found.")}
    end
  end

  @impl true
  def handle_event("move_hero_slide_up", %{"slide-id" => slide_id}, socket) do
    reorder_hero_slide(socket, slide_id, :up)
  end

  @impl true
  def handle_event("move_hero_slide_down", %{"slide-id" => slide_id}, socket) do
    reorder_hero_slide(socket, slide_id, :down)
  end

  @impl true
  def handle_event("save_hero_auto_advance", %{"auto_advance_ms" => ms_str}, socket) do
    scope = socket.assigns.current_scope
    hero_row = socket.assigns.hero_row

    if hero_row do
      ms = String.to_integer(ms_str)
      config = Map.merge(hero_row.filter_config || %{}, %{"auto_advance_ms" => ms})
      {:ok, _} = Catalog.update_row(scope, hero_row, %{filter_config: config})

      Process.send_after(self(), {:clear_hero_save_status, "auto_advance"}, 3_000)

      {:noreply,
       socket
       |> put_flash(:info, "Auto-rotate setting saved.")
       |> update(:hero_save_status, &Map.put(&1, "auto_advance", :ok))
       |> load_hero_row()}
    else
      {:noreply, socket}
    end
  end

  # ── Save status auto-clear ──────────────────────────────────────────────

  @impl true
  def handle_info({:clear_hero_save_status, key}, socket) do
    {:noreply, update(socket, :hero_save_status, &Map.delete(&1, key))}
  end

  # ── PubSub ─────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:bobine_event, _event, _scope}, socket) do
    {:noreply, load_rows(socket)}
  end

  # ── Render ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <BobineWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <.header>Catalog</.header>
      <%= if @selected_row && @row_videos != [] || (@selected_row && @selected_row.source_type == :curated && @preview_videos == []) do %>
        <.row_items_view
          row={@selected_row}
          videos={@row_videos}
          can_manage={@can_manage}
          show_video_picker={@show_video_picker}
          available_videos={@available_videos}
        />
      <% else %>
        <%!-- Hero editor section --%>
        <.hero_editor
          hero_row={@hero_row}
          hero_slides={@hero_slides}
          can_manage={@can_manage}
          show_hero_video_picker={@show_hero_video_picker}
          hero_available_videos={@hero_available_videos}
          hero_save_status={@hero_save_status}
          hero_collapsed={@hero_collapsed}
        />

        <div class="divider my-8" />

        <%!-- Regular rows list --%>
        <.rows_list_view
          rows={@rows}
          can_manage={@can_manage}
          show_form={@show_form}
          form={@form}
          editing_row={@editing_row}
          source_types={@source_types}
          collections={@collections}
          tags={@tags}
          selected_row={@selected_row}
          preview_videos={@preview_videos}
        />
      <% end %>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  # ── Hero editor component ──────────────────────────────────────────────

  defp hero_editor(assigns) do
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

  # ── Rows list ──────────────────────────────────────────────────────────

  defp rows_list_view(assigns) do
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

  defp row_form(assigns) do
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

  defp row_preview(assigns) do
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

  defp row_items_view(assigns) do
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

  # ── Data loading ───────────────────────────────────────────────────────

  defp load_rows(socket) do
    org = socket.assigns.organization
    %{results: rows} = Catalog.list_rows(org)
    # Filter hero rows from the regular rows list — hero is managed separately
    non_hero_rows = Enum.reject(rows, &(&1.source_type == :hero))
    assign(socket, :rows, non_hero_rows)
  end

  defp load_hero_row(socket) do
    org = socket.assigns.organization

    case Catalog.get_hero_row(org) do
      {:ok, row} ->
        socket
        |> assign(:hero_row, row)
        |> load_hero_slides()

      {:error, :not_found} ->
        assign(socket, hero_row: nil, hero_slides: [])
    end
  end

  defp load_hero_slides(socket) do
    org = socket.assigns.organization
    hero_row = socket.assigns.hero_row

    if hero_row do
      enriched = Catalog.list_enriched_hero_slides(org, hero_row)
      assign(socket, :hero_slides, enriched)
    else
      assign(socket, :hero_slides, [])
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  defp reorder_row(socket, id, direction) do
    rows = socket.assigns.rows
    index = Enum.find_index(rows, &(&1.id == id))

    new_index =
      case direction do
        :up -> max(0, index - 1)
        :down -> min(length(rows) - 1, index + 1)
      end

    if index != new_index do
      scope = socket.assigns.current_scope
      reordered = swap(rows, index, new_index)
      ordered_ids = Enum.map(reordered, & &1.id)
      :ok = Catalog.reorder_rows(scope, ordered_ids)
      {:noreply, load_rows(socket)}
    else
      {:noreply, socket}
    end
  end

  defp reorder_hero_slide(socket, slide_id, direction) do
    slides = socket.assigns.hero_slides
    index = Enum.find_index(slides, &(&1.id == slide_id))

    new_index =
      case direction do
        :up -> max(0, index - 1)
        :down -> min(length(slides) - 1, index + 1)
      end

    if index != new_index do
      scope = socket.assigns.current_scope
      hero_row = socket.assigns.hero_row
      reordered = swap(slides, index, new_index)
      ordered_ids = Enum.map(reordered, & &1.id)
      :ok = Catalog.reorder_hero_slides(scope, hero_row, ordered_ids)
      {:noreply, load_hero_slides(socket)}
    else
      {:noreply, socket}
    end
  end

  defp swap(list, i, j) do
    list
    |> List.replace_at(i, Enum.at(list, j))
    |> List.replace_at(j, Enum.at(list, i))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(str) when is_binary(str), do: str

  defp source_type_label(:curated), do: "Curated"
  defp source_type_label(:collection), do: "Collection"
  defp source_type_label(:tag), do: "Tag"
  defp source_type_label(:recent), do: "Recent"
  defp source_type_label(:popular), do: "Popular"
  defp source_type_label(:continue_watching), do: "Continue Watching"
  defp source_type_label(:hero), do: "Hero"
  defp source_type_label(other), do: to_string(other)

  defp show_source_select?(current, target) do
    to_string(current) == to_string(target)
  end

  defp hero_auto_advance_ms(%{filter_config: config}) when is_map(config) do
    Map.get(config, "auto_advance_ms", 8000)
  end

  defp hero_auto_advance_ms(_), do: 8000
end
