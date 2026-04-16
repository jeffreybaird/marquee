defmodule BobineWeb.Admin.CollectionsLive do
  @moduledoc """
  Collection management. CRUD operations for content collections,
  item picker for assigning videos, seasons, and series to collections,
  real-time updates via Events.

  Events: new_collection, edit_collection, save_collection, delete_collection,
          select_collection, add_item, remove_item
  Route: /admin/collections
  """

  use BobineWeb, :live_view
  use BobineWeb.Admin.ImageUploadHandlers

  alias Bobine.Accounts
  alias Bobine.Content
  alias Bobine.Content.Collection
  alias Bobine.Events
  alias BobineWeb.Admin.ImageUploadHandlers

  @impl true
  def allowed_upload_kind?("collection_cover"), do: true
  def allowed_upload_kind?(_), do: false

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
     |> assign(:page_title, "Collections")
     |> assign(:can_manage, can_manage)
     |> assign(:show_form, false)
     |> assign(:editing_collection, nil)
     |> assign(:show_item_picker, false)
     |> assign(:selected_collection, nil)
     |> assign(:collection_items, [])
     |> assign(:picker_type, :video)
     |> assign(:picker_videos, [])
     |> assign(:picker_seasons, [])
     |> assign(:picker_series, [])
     |> assign(:selected_video_ids, MapSet.new())
     |> assign(:form, nil)
     |> load_collections()}
  end

  @impl true
  def handle_event("new_collection", _params, socket) do
    form =
      Content.change_collection(%Collection{})
      |> to_form()

    socket =
      socket
      |> ImageUploadHandlers.put_initial_url(
        "collection_cover",
        collection_cover_target(nil),
        nil
      )
      |> assign(show_form: true, editing_collection: nil, form: form)

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_collection", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Content.get_collection(org, id) do
      {:ok, collection} ->
        form = Content.change_collection(collection) |> to_form()

        socket =
          socket
          |> ImageUploadHandlers.put_initial_url(
            "collection_cover",
            collection_cover_target(collection),
            collection.cover_image_url
          )
          |> assign(show_form: true, editing_collection: collection, form: form)

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Collection not found.")}
    end
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, show_form: false, editing_collection: nil, form: nil)}
  end

  @impl true
  def handle_event("save_collection", %{"collection" => params}, socket) do
    scope = socket.assigns.current_scope

    target_id = collection_cover_target(socket.assigns.editing_collection)
    uploaded_url = ImageUploadHandlers.upload_url(socket, "collection_cover", target_id)
    params = maybe_put_cover_image_url(params, uploaded_url)

    result =
      case socket.assigns.editing_collection do
        nil ->
          Content.create_collection(scope, params)

        collection ->
          Content.update_collection(scope, collection, params)
      end

    case result do
      {:ok, _collection} ->
        {:noreply,
         socket
         |> assign(show_form: false, editing_collection: nil, form: nil)
         |> put_flash(:info, "Collection saved.")
         |> load_collections()}

      {:error, :validation, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete_collection", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Content.get_collection(org, id) do
      {:ok, collection} ->
        {:ok, _} = Content.delete_collection(scope, collection)

        {:noreply,
         socket
         |> put_flash(:info, "Collection deleted.")
         |> load_collections()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Collection not found.")}
    end
  end

  @impl true
  def handle_event("toggle_visibility", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Content.get_collection(org, id) do
      {:ok, collection} ->
        {:ok, _} =
          Content.update_collection(scope, collection, %{visible: !collection.visible})

        {:noreply, load_collections(socket)}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("view_collection", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Content.get_collection(org, id) do
      {:ok, collection} ->
        %{results: items} = Content.list_collection_items(org, collection)

        {:noreply,
         assign(socket,
           selected_collection: collection,
           collection_items: items
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Collection not found.")}
    end
  end

  @impl true
  def handle_event("back_to_list", _params, socket) do
    {:noreply,
     assign(socket,
       selected_collection: nil,
       collection_items: [],
       show_item_picker: false,
       picker_type: :video,
       picker_videos: [],
       picker_seasons: [],
       picker_series: [],
       selected_video_ids: MapSet.new()
     )}
  end

  # Keep legacy event name for backward compatibility
  @impl true
  def handle_event("open_video_picker", _params, socket) do
    handle_event("open_item_picker", %{}, socket)
  end

  @impl true
  def handle_event("open_item_picker", _params, socket) do
    socket = load_picker_content(socket, :video)
    {:noreply, assign(socket, show_item_picker: true, picker_type: :video)}
  end

  @impl true
  def handle_event("close_video_picker", _params, socket) do
    handle_event("close_item_picker", %{}, socket)
  end

  @impl true
  def handle_event("close_item_picker", _params, socket) do
    {:noreply,
     assign(socket,
       show_item_picker: false,
       picker_videos: [],
       picker_seasons: [],
       picker_series: [],
       selected_video_ids: MapSet.new()
     )}
  end

  @impl true
  def handle_event("set_picker_type", %{"type" => type}, socket) do
    picker_type = String.to_existing_atom(type)
    socket = load_picker_content(socket, picker_type)
    {:noreply, assign(socket, picker_type: picker_type, selected_video_ids: MapSet.new())}
  end

  @impl true
  def handle_event("toggle_video_selection", %{"video-id" => video_id}, socket) do
    selected = socket.assigns.selected_video_ids

    updated =
      if MapSet.member?(selected, video_id) do
        MapSet.delete(selected, video_id)
      else
        MapSet.put(selected, video_id)
      end

    {:noreply, assign(socket, selected_video_ids: updated)}
  end

  @impl true
  def handle_event("add_selected_videos", _params, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    collection = socket.assigns.selected_collection
    selected_ids = socket.assigns.selected_video_ids

    if MapSet.size(selected_ids) == 0 do
      {:noreply, put_flash(socket, :error, "No videos selected.")}
    else
      videos = resolve_videos(org, selected_ids)

      case Content.add_videos_to_collection(scope, collection, videos) do
        {:ok, items} ->
          %{results: collection_items} = Content.list_collection_items(org, collection)
          count = length(items)

          {:noreply,
           socket
           |> assign(
             collection_items: collection_items,
             show_item_picker: false,
             picker_videos: [],
             selected_video_ids: MapSet.new()
           )
           |> put_flash(
             :info,
             "#{count} video#{if count != 1, do: "s", else: ""} added to collection."
           )}

        {:error, {:validation, _changeset}} ->
          {:noreply, put_flash(socket, :error, "Failed to add videos.")}
      end
    end
  end

  @impl true
  def handle_event("add_item_to_collection", %{"type" => type, "id" => id}, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization
    collection = socket.assigns.selected_collection

    result =
      case type do
        "season" ->
          season = Content.get_season!(org, id)
          Content.add_season_to_collection(scope, collection, season)

        "series" ->
          series = Content.get_series!(org, id)
          Content.add_series_to_collection(scope, collection, series)
      end

    case result do
      {:ok, _item} ->
        %{results: items} = Content.list_collection_items(org, collection)

        {:noreply,
         socket
         |> assign(collection_items: items)
         |> load_picker_content(socket.assigns.picker_type)
         |> put_flash(:info, "#{String.capitalize(type)} added to collection.")}

      {:error, :already_exists} ->
        {:noreply, put_flash(socket, :error, "Already in this collection.")}

      {:error, _, _} ->
        {:noreply, put_flash(socket, :error, "Could not add item to collection.")}
    end
  end

  @impl true
  def handle_event("remove_item", %{"item-id" => item_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    collection = socket.assigns.selected_collection

    %{results: items} = Content.list_collection_items(org, collection)

    case Enum.find(items, &(&1.id == item_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Item not found.")}

      item ->
        :ok = Content.remove_collection_item(scope, item)
        %{results: updated_items} = Content.list_collection_items(org, collection)

        {:noreply,
         socket
         |> assign(collection_items: updated_items)
         |> put_flash(:info, "Item removed from collection.")}
    end
  end

  @impl true
  def handle_event("remove_video", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    collection = socket.assigns.selected_collection

    case Content.get_video(org, video_id) do
      {:ok, video} ->
        :ok = Content.remove_video_from_collection(scope, collection, video)
        %{results: items} = Content.list_collection_items(org, collection)

        {:noreply,
         socket
         |> assign(collection_items: items)
         |> put_flash(:info, "Video removed from collection.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Video not found.")}
    end
  end

  @impl true
  def handle_event("move_up", %{"id" => id}, socket) do
    reorder_collection(socket, id, :up)
  end

  @impl true
  def handle_event("move_down", %{"id" => id}, socket) do
    reorder_collection(socket, id, :down)
  end

  @impl true
  def handle_event("move_item_up", %{"item-id" => item_id}, socket) do
    reorder_item_in_collection(socket, item_id, :up)
  end

  @impl true
  def handle_event("move_item_down", %{"item-id" => item_id}, socket) do
    reorder_item_in_collection(socket, item_id, :down)
  end

  # Keep legacy video reorder events for backward compatibility
  @impl true
  def handle_event("move_video_up", %{"video-id" => video_id}, socket) do
    reorder_video_in_collection(socket, video_id, :up)
  end

  @impl true
  def handle_event("move_video_down", %{"video-id" => video_id}, socket) do
    reorder_video_in_collection(socket, video_id, :down)
  end

  @impl true
  def handle_info({:bobine_event, _event, _scope}, socket) do
    {:noreply, load_collections(socket)}
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
      <%= if @selected_collection do %>
        <.collection_detail_view
          collection={@selected_collection}
          items={@collection_items}
          can_manage={@can_manage}
          show_item_picker={@show_item_picker}
          picker_type={@picker_type}
          picker_videos={@picker_videos}
          picker_seasons={@picker_seasons}
          picker_series={@picker_series}
          selected_video_ids={@selected_video_ids}
        />
      <% else %>
        <.collections_list_view
          collections={@collections}
          can_manage={@can_manage}
          show_form={@show_form}
          form={@form}
          editing_collection={@editing_collection}
          collection_cover_target={collection_cover_target(@editing_collection)}
          collection_cover_state={
            ImageUploadHandlers.upload_state(
              @image_uploads,
              "collection_cover",
              collection_cover_target(@editing_collection)
            )
          }
        />
      <% end %>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp collections_list_view(assigns) do
    ~H"""
    <BobineWeb.Components.AdminUI.admin_panel
      title="Collections"
      subtitle="Group videos, seasons, and series for the viewer catalog."
    >
      <:actions>
        <BobineWeb.Components.AdminUI.admin_button
          :if={@can_manage}
          phx-click="new_collection"
          size={:sm}
          data-test="new-collection-btn"
        >
          New Collection
        </BobineWeb.Components.AdminUI.admin_button>
      </:actions>

      <BobineWeb.Components.AdminUI.admin_empty
        :if={@collections == []}
        title="No collections yet"
        description="Create your first collection to organize videos."
        data_test="empty-state"
      />

      <div
        :if={@collections != []}
        data-test="collections-list"
        class="overflow-x-auto rounded-lg border border-admin-border bg-admin-card"
      >
        <table class="w-full font-body text-sm text-admin-fg">
          <thead class="border-b border-admin-border bg-admin-card">
            <tr class="text-left font-ui text-xs uppercase tracking-wide text-admin-muted">
              <th class="px-4 py-3">Title</th>
              <th class="px-4 py-3">Visible</th>
              <th class="px-4 py-3">Position</th>
              <th class="px-4 py-3"></th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={collection <- @collections}
              class="border-t border-admin-border"
              data-test={"collection-row-#{collection.id}"}
            >
              <td class="px-4 py-3">
                <button
                  phx-click="view_collection"
                  phx-value-id={collection.id}
                  class="font-display font-semibold text-admin-fg hover:text-admin-accent hover:underline"
                >
                  {collection.title}
                </button>
                <div class="font-mono text-xs text-admin-muted">{collection.slug}</div>
              </td>
              <td class="px-4 py-3">
                <button
                  :if={@can_manage}
                  phx-click="toggle_visibility"
                  phx-value-id={collection.id}
                  data-test="collection-visibility-toggle"
                  class={[
                    "rounded-full border px-2 py-0.5 font-ui text-xs",
                    if(collection.visible,
                      do: "border-transparent bg-admin-accent/10 text-admin-accent",
                      else: "border-admin-border text-admin-muted"
                    )
                  ]}
                >
                  {if collection.visible, do: "Visible", else: "Hidden"}
                </button>
                <span
                  :if={!@can_manage}
                  class="rounded-full border border-admin-border px-2 py-0.5 font-ui text-xs text-admin-muted"
                >
                  {if collection.visible, do: "Visible", else: "Hidden"}
                </span>
              </td>
              <td class="px-4 py-3">
                <div class="flex gap-1">
                  <BobineWeb.Components.AdminUI.admin_button
                    :if={@can_manage}
                    variant={:ghost}
                    size={:sm}
                    phx-click="move_up"
                    phx-value-id={collection.id}
                  >
                    ↑
                  </BobineWeb.Components.AdminUI.admin_button>
                  <BobineWeb.Components.AdminUI.admin_button
                    :if={@can_manage}
                    variant={:ghost}
                    size={:sm}
                    phx-click="move_down"
                    phx-value-id={collection.id}
                  >
                    ↓
                  </BobineWeb.Components.AdminUI.admin_button>
                </div>
              </td>
              <td :if={@can_manage} class="px-4 py-3">
                <div class="flex justify-end gap-1">
                  <BobineWeb.Components.AdminUI.admin_button
                    variant={:secondary}
                    size={:sm}
                    phx-click="edit_collection"
                    phx-value-id={collection.id}
                  >
                    Edit
                  </BobineWeb.Components.AdminUI.admin_button>
                  <BobineWeb.Components.AdminUI.admin_button
                    variant={:danger}
                    size={:sm}
                    phx-click="delete_collection"
                    phx-value-id={collection.id}
                    data-confirm="Are you sure?"
                    data-test={"delete-collection-#{collection.id}"}
                  >
                    Delete
                  </BobineWeb.Components.AdminUI.admin_button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </BobineWeb.Components.AdminUI.admin_panel>

    <BobineWeb.Components.AdminUI.admin_sheet
      id="collection-sheet"
      open={@show_form}
      title={if @editing_collection, do: "Edit Collection", else: "New Collection"}
      on_close="cancel_form"
      data_test="collection-form"
    >
      <.form
        for={@form}
        id="collection-form"
        phx-submit="save_collection"
        class="space-y-4"
      >
        <div>
          <label
            class="mb-1 block font-ui text-sm font-medium text-admin-fg"
            for="collection-title"
          >
            Title
          </label>
          <input
            type="text"
            id="collection-title"
            name="collection[title]"
            value={@form[:title].value}
            required
            class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
            data-test="collection-title-input"
          />
          <.field_error :for={msg <- error_messages(@form[:title])}>
            {msg}
          </.field_error>
        </div>

        <div>
          <label
            class="mb-1 block font-ui text-sm font-medium text-admin-fg"
            for="collection-description"
          >
            Description
          </label>
          <textarea
            id="collection-description"
            name="collection[description]"
            rows="3"
            class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
          >{@form[:description].value}</textarea>
        </div>

        <div>
          <BobineWeb.Components.AdminComponents.image_upload_field
            name="collection[cover_image_url]"
            kind="collection_cover"
            target_id={@collection_cover_target}
            url={@collection_cover_state.url}
            status={@collection_cover_state.status}
            percent={@collection_cover_state.percent}
            error={@collection_cover_state.error}
            label="Cover image"
            help="JPG, PNG or WebP. Optional."
          />
        </div>
      </.form>

      <:footer>
        <BobineWeb.Components.AdminUI.admin_button
          variant={:ghost}
          phx-click="cancel_form"
        >
          Cancel
        </BobineWeb.Components.AdminUI.admin_button>
        <BobineWeb.Components.AdminUI.admin_button
          type="submit"
          form="collection-form"
          data-test="save-collection-btn"
        >
          Save
        </BobineWeb.Components.AdminUI.admin_button>
      </:footer>
    </BobineWeb.Components.AdminUI.admin_sheet>
    """
  end

  defp collection_detail_view(assigns) do
    assigns = assign(assigns, :selected_count, MapSet.size(assigns.selected_video_ids))

    ~H"""
    <BobineWeb.Components.AdminUI.admin_panel
      title={@collection.title}
      subtitle={@collection.description}
    >
      <:actions>
        <BobineWeb.Components.AdminUI.admin_button
          variant={:ghost}
          size={:sm}
          phx-click="back_to_list"
        >
          ← Back
        </BobineWeb.Components.AdminUI.admin_button>
        <BobineWeb.Components.AdminUI.admin_button
          :if={@can_manage}
          size={:sm}
          phx-click="open_item_picker"
          data-test="add-videos-btn"
        >
          Add Items
        </BobineWeb.Components.AdminUI.admin_button>
      </:actions>

      <BobineWeb.Components.AdminUI.admin_empty
        :if={@items == []}
        title="No items yet"
        description="Add videos, seasons, or series to this collection."
      />

      <div :if={@items != []} class="space-y-2">
        <div
          :for={item <- @items}
          class="flex items-center gap-3 rounded-lg border border-admin-border bg-admin-card p-3"
          data-test={item_test_id(item)}
        >
          <%= case item.item_type do %>
            <% :video -> %>
              <div class="h-12 w-20 flex-shrink-0 overflow-hidden rounded bg-admin-card">
                <img
                  :if={item.video && item.video.mux_playback_id}
                  src={"https://image.mux.com/#{item.video.mux_playback_id}/thumbnail.webp?width=160&height=96"}
                  alt={item.video && item.video.title}
                  class="h-full w-full object-cover"
                />
              </div>
              <div class="min-w-0 flex-1">
                <div class="truncate font-display font-semibold text-admin-fg">
                  {item.video && item.video.title}
                </div>
              </div>
              <span
                class="rounded-full border border-admin-border px-2 py-0.5 font-ui text-xs text-admin-muted"
                data-test="type-badge"
              >
                Video
              </span>
            <% :season -> %>
              <div class="h-12 w-20 flex-shrink-0 overflow-hidden rounded bg-admin-card">
                <img
                  :if={item.season && item.season.cover_image_url}
                  src={item.season.cover_image_url}
                  alt={item.season && item.season.title}
                  class="h-full w-full object-cover"
                />
              </div>
              <div class="min-w-0 flex-1">
                <div class="truncate font-display font-semibold text-admin-fg">
                  {item.season && item.season.title}
                </div>
                <div class="font-mono text-xs text-admin-muted">
                  {item.season && item.season.episode_count} episodes
                </div>
              </div>
              <span
                class="rounded-full bg-admin-accent/10 px-2 py-0.5 font-ui text-xs text-admin-accent"
                data-test="type-badge"
              >
                Season
              </span>
            <% :series -> %>
              <div class="h-12 w-20 flex-shrink-0 overflow-hidden rounded bg-admin-card">
                <img
                  :if={item.series && item.series.cover_image_url}
                  src={item.series.cover_image_url}
                  alt={item.series && item.series.title}
                  class="h-full w-full object-cover"
                />
              </div>
              <div class="min-w-0 flex-1">
                <div class="truncate font-display font-semibold text-admin-fg">
                  {item.series && item.series.title}
                </div>
              </div>
              <span
                class="rounded-full bg-admin-accent/10 px-2 py-0.5 font-ui text-xs text-admin-accent"
                data-test="type-badge"
              >
                Series
              </span>
          <% end %>

          <div :if={@can_manage} class="flex gap-1">
            <BobineWeb.Components.AdminUI.admin_button
              variant={:ghost}
              size={:sm}
              phx-click="move_item_up"
              phx-value-item-id={item.id}
            >
              ↑
            </BobineWeb.Components.AdminUI.admin_button>
            <BobineWeb.Components.AdminUI.admin_button
              variant={:ghost}
              size={:sm}
              phx-click="move_item_down"
              phx-value-item-id={item.id}
            >
              ↓
            </BobineWeb.Components.AdminUI.admin_button>
            <BobineWeb.Components.AdminUI.admin_button
              variant={:danger}
              size={:sm}
              phx-click="remove_item"
              phx-value-item-id={item.id}
              data-confirm="Remove item from collection?"
              data-test={remove_test_id(item)}
            >
              Remove
            </BobineWeb.Components.AdminUI.admin_button>
          </div>
        </div>
      </div>
    </BobineWeb.Components.AdminUI.admin_panel>

    <BobineWeb.Components.AdminUI.admin_sheet
      id="collection-item-picker"
      open={@show_item_picker}
      title="Add Items"
      subtitle="Pick videos, seasons, or series to include."
      on_close="close_item_picker"
      data_test="collection-item-picker"
    >
      <div class="mb-4 flex gap-1" data-test="picker-type-tabs">
        <BobineWeb.Components.AdminUI.admin_button
          variant={if @picker_type == :video, do: :accent, else: :ghost}
          size={:sm}
          phx-click="set_picker_type"
          phx-value-type="video"
          data-test="picker-type-video"
        >
          Videos
        </BobineWeb.Components.AdminUI.admin_button>
        <BobineWeb.Components.AdminUI.admin_button
          variant={if @picker_type == :season, do: :accent, else: :ghost}
          size={:sm}
          phx-click="set_picker_type"
          phx-value-type="season"
          data-test="picker-type-season"
        >
          Seasons
        </BobineWeb.Components.AdminUI.admin_button>
        <BobineWeb.Components.AdminUI.admin_button
          variant={if @picker_type == :series, do: :accent, else: :ghost}
          size={:sm}
          phx-click="set_picker_type"
          phx-value-type="series"
          data-test="picker-type-series"
        >
          Series
        </BobineWeb.Components.AdminUI.admin_button>
      </div>

      <div class="space-y-2" data-test="picker-results">
        <%= case @picker_type do %>
          <% :video -> %>
            <div
              :if={@picker_videos == []}
              class="py-4 text-center font-body text-sm text-admin-muted"
            >
              All videos are already in this collection.
            </div>
            <div
              :for={video <- @picker_videos}
              class="flex items-center gap-3 rounded border border-admin-border bg-admin-card p-2"
            >
              <label class="flex min-w-0 flex-1 cursor-pointer items-center gap-3">
                <input
                  type="checkbox"
                  class="size-4 rounded border-admin-border text-admin-accent focus-visible:outline-admin-accent"
                  checked={MapSet.member?(@selected_video_ids, video.id)}
                  phx-click="toggle_video_selection"
                  phx-value-video-id={video.id}
                  data-test={"select-video-#{video.id}"}
                />
                <span class="truncate font-body text-sm text-admin-fg">
                  {video.title}
                </span>
              </label>
            </div>
          <% :season -> %>
            <div
              :if={@picker_seasons == []}
              class="py-4 text-center font-body text-sm text-admin-muted"
            >
              No seasons available.
            </div>
            <div
              :for={season <- @picker_seasons}
              class="flex cursor-pointer items-center gap-3 rounded border border-admin-border bg-admin-card p-2 hover:border-admin-border"
              phx-click="add_item_to_collection"
              phx-value-type="season"
              phx-value-id={season.id}
              data-test={"picker-item-season-#{season.id}"}
            >
              <div class="min-w-0 flex-1">
                <span class="font-display font-semibold text-admin-fg">
                  {season.title}
                </span>
                <span class="ml-2 font-mono text-xs text-admin-muted">
                  {season.episode_count} episodes
                </span>
              </div>
              <span class="rounded-full bg-admin-accent/10 px-2 py-0.5 font-ui text-xs text-admin-accent">
                Season
              </span>
            </div>
          <% :series -> %>
            <div
              :if={@picker_series == []}
              class="py-4 text-center font-body text-sm text-admin-muted"
            >
              No series available.
            </div>
            <div
              :for={series <- @picker_series}
              class="flex cursor-pointer items-center gap-3 rounded border border-admin-border bg-admin-card p-2 hover:border-admin-border"
              phx-click="add_item_to_collection"
              phx-value-type="series"
              phx-value-id={series.id}
              data-test={"picker-item-series-#{series.id}"}
            >
              <div class="min-w-0 flex-1">
                <span class="font-display font-semibold text-admin-fg">
                  {series.title}
                </span>
              </div>
              <span class="rounded-full bg-admin-accent/10 px-2 py-0.5 font-ui text-xs text-admin-accent">
                Series
              </span>
            </div>
        <% end %>
      </div>

      <:footer>
        <span
          :if={@picker_type == :video && @picker_videos != []}
          class="mr-auto font-mono text-sm text-admin-muted"
        >
          {@selected_count} selected
        </span>
        <BobineWeb.Components.AdminUI.admin_button
          variant={:ghost}
          phx-click="close_item_picker"
        >
          Cancel
        </BobineWeb.Components.AdminUI.admin_button>
        <BobineWeb.Components.AdminUI.admin_button
          :if={@picker_type == :video && @picker_videos != []}
          phx-click="add_selected_videos"
          disabled={@selected_count == 0}
          data-test="add-selected-videos-btn"
        >
          Add Selected
        </BobineWeb.Components.AdminUI.admin_button>
      </:footer>
    </BobineWeb.Components.AdminUI.admin_sheet>
    """
  end

  defp load_collections(socket) do
    org = socket.assigns.organization
    %{results: collections} = Content.list_collections(org)
    assign(socket, :collections, collections)
  end

  defp collection_cover_target(nil), do: "new"
  defp collection_cover_target(%Collection{id: id}), do: id
  defp collection_cover_target(%{id: id}), do: id

  defp maybe_put_cover_image_url(params, nil), do: params
  defp maybe_put_cover_image_url(params, ""), do: params

  defp maybe_put_cover_image_url(params, url) when is_binary(url) do
    Map.put(params, "cover_image_url", url)
  end

  defp load_picker_content(socket, :video) do
    org = socket.assigns.organization
    collection = socket.assigns.selected_collection
    %{results: all_videos} = Content.list_videos(org, per_page: 100)
    %{results: collection_items} = Content.list_collection_items(org, collection, per_page: 100)

    collection_video_ids =
      collection_items
      |> Enum.filter(&(&1.item_type == :video))
      |> MapSet.new(& &1.video_id)

    available = Enum.reject(all_videos, &MapSet.member?(collection_video_ids, &1.id))
    assign(socket, picker_videos: available)
  end

  defp load_picker_content(socket, :season) do
    org = socket.assigns.organization
    %{results: all_series} = Content.list_series(org, per_page: 100)

    seasons =
      Enum.flat_map(all_series, fn s ->
        %{results: seasons} = Content.list_seasons(org, s, per_page: 100)
        seasons
      end)

    assign(socket, picker_seasons: seasons)
  end

  defp load_picker_content(socket, :series) do
    org = socket.assigns.organization
    %{results: series_list} = Content.list_series(org, per_page: 100)
    assign(socket, picker_series: series_list)
  end

  defp reorder_collection(socket, id, direction) do
    collections = socket.assigns.collections
    index = Enum.find_index(collections, &(&1.id == id))

    new_index =
      case direction do
        :up -> max(0, index - 1)
        :down -> min(length(collections) - 1, index + 1)
      end

    if index != new_index do
      scope = socket.assigns.current_scope
      reordered = swap(collections, index, new_index)
      ordered_ids = Enum.map(reordered, & &1.id)
      :ok = Content.reorder_collections(scope, ordered_ids)
      {:noreply, load_collections(socket)}
    else
      {:noreply, socket}
    end
  end

  defp reorder_item_in_collection(socket, item_id, direction) do
    items = socket.assigns.collection_items
    index = Enum.find_index(items, &(&1.id == item_id))

    new_index =
      case direction do
        :up -> max(0, index - 1)
        :down -> min(length(items) - 1, index + 1)
      end

    if index != new_index do
      scope = socket.assigns.current_scope
      collection = socket.assigns.selected_collection
      reordered = swap(items, index, new_index)
      ordered_ids = Enum.map(reordered, & &1.id)
      :ok = Content.reorder_collection_items(scope, collection, ordered_ids)

      org = socket.assigns.organization
      %{results: items} = Content.list_collection_items(org, collection)
      {:noreply, assign(socket, collection_items: items)}
    else
      {:noreply, socket}
    end
  end

  defp reorder_video_in_collection(socket, video_id, direction) do
    items = socket.assigns.collection_items
    index = Enum.find_index(items, &(&1.video_id == video_id))

    if index do
      item_id = Enum.at(items, index).id
      reorder_item_in_collection(socket, item_id, direction)
    else
      {:noreply, socket}
    end
  end

  defp swap(list, i, j) do
    list
    |> List.replace_at(i, Enum.at(list, j))
    |> List.replace_at(j, Enum.at(list, i))
  end

  defp resolve_videos(org, selected_ids) do
    Enum.reduce(selected_ids, [], fn id, acc ->
      case Content.get_video(org, id) do
        {:ok, video} -> [video | acc]
        _ -> acc
      end
    end)
  end

  # For video items, use the legacy data-test="collection-video-<video_id>" format
  # so existing tests keep working. Non-video items use the new item-based format.
  defp item_test_id(%{item_type: :video, video_id: vid}), do: "collection-video-#{vid}"
  defp item_test_id(%{id: id}), do: "collection-item-#{id}"

  defp remove_test_id(%{item_type: :video, video_id: vid}), do: "remove-video-#{vid}"
  defp remove_test_id(%{id: id}), do: "remove-item-#{id}"

  defp error_messages(field) do
    Enum.map(field.errors, fn {msg, _opts} -> msg end)
  end

  defp field_error(assigns) do
    ~H"""
    <p class="text-error text-sm mt-1">{render_slot(@inner_block)}</p>
    """
  end
end
