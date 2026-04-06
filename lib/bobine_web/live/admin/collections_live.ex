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

  alias Bobine.Accounts
  alias Bobine.Content
  alias Bobine.Events

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
      Content.change_collection(%Bobine.Content.Collection{})
      |> to_form()

    {:noreply,
     assign(socket,
       show_form: true,
       editing_collection: nil,
       form: form
     )}
  end

  @impl true
  def handle_event("edit_collection", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Content.get_collection(org, id) do
      {:ok, collection} ->
        form = Content.change_collection(collection) |> to_form()

        {:noreply,
         assign(socket,
           show_form: true,
           editing_collection: collection,
           form: form
         )}

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
        />
      <% end %>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp collections_list_view(assigns) do
    ~H"""
    <div class="flex items-center justify-between pb-4">
      <.header>Collections</.header>
      <button
        :if={@can_manage}
        phx-click="new_collection"
        class="btn btn-primary"
        data-test="new-collection-btn"
      >
        New Collection
      </button>
    </div>

    <div
      :if={@collections == []}
      class="py-12 text-center text-base-content/60"
      data-test="empty-state"
    >
      <p class="text-lg">No collections yet.</p>
      <p class="mt-2">Create your first collection to organize videos.</p>
    </div>

    <div :if={@collections != []} data-test="collections-list" class="overflow-x-auto">
      <table class="table w-full">
        <thead>
          <tr>
            <th>Title</th>
            <th>Visible</th>
            <th>Position</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={collection <- @collections} data-test={"collection-row-#{collection.id}"}>
            <td>
              <button
                phx-click="view_collection"
                phx-value-id={collection.id}
                class="font-medium hover:text-primary hover:underline"
              >
                {collection.title}
              </button>
              <div class="text-xs text-base-content/60 font-mono">{collection.slug}</div>
            </td>
            <td>
              <button
                :if={@can_manage}
                phx-click="toggle_visibility"
                phx-value-id={collection.id}
                data-test="collection-visibility-toggle"
                class={"badge badge-sm #{if collection.visible, do: "badge-success", else: "badge-ghost"}"}
              >
                {if collection.visible, do: "Visible", else: "Hidden"}
              </button>
              <span :if={!@can_manage} class="badge badge-sm badge-ghost">
                {if collection.visible, do: "Visible", else: "Hidden"}
              </span>
            </td>
            <td class="flex gap-1">
              <button
                :if={@can_manage}
                phx-click="move_up"
                phx-value-id={collection.id}
                class="btn btn-xs btn-ghost"
              >
                ↑
              </button>
              <button
                :if={@can_manage}
                phx-click="move_down"
                phx-value-id={collection.id}
                class="btn btn-xs btn-ghost"
              >
                ↓
              </button>
            </td>
            <td :if={@can_manage}>
              <div class="flex gap-1">
                <button
                  phx-click="edit_collection"
                  phx-value-id={collection.id}
                  class="btn btn-xs btn-outline"
                >
                  Edit
                </button>
                <button
                  phx-click="delete_collection"
                  phx-value-id={collection.id}
                  data-confirm="Are you sure?"
                  class="btn btn-xs btn-outline btn-error"
                  data-test={"delete-collection-#{collection.id}"}
                >
                  Delete
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <.collection_form :if={@show_form} form={@form} editing={@editing_collection} />
    """
  end

  defp collection_form(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div class="bg-base-100 rounded-lg p-6 w-full max-w-md shadow-xl">
        <h3 class="text-lg font-semibold mb-4">
          {if @editing, do: "Edit Collection", else: "New Collection"}
        </h3>
        <.form for={@form} phx-submit="save_collection" data-test="collection-form">
          <div class="mb-4">
            <label class="label" for="collection-title">Title</label>
            <input
              type="text"
              id="collection-title"
              name="collection[title]"
              value={@form[:title].value}
              required
              class="input input-bordered w-full"
              data-test="collection-title-input"
            />
            <.field_error :for={msg <- error_messages(@form[:title])}>
              {msg}
            </.field_error>
          </div>
          <div class="mb-4">
            <label class="label" for="collection-description">Description</label>
            <textarea
              id="collection-description"
              name="collection[description]"
              class="textarea textarea-bordered w-full"
              rows="3"
            >{@form[:description].value}</textarea>
          </div>
          <div class="mb-4">
            <label class="label" for="collection-cover">Cover Image URL</label>
            <input
              type="text"
              id="collection-cover"
              name="collection[cover_image_url]"
              value={@form[:cover_image_url].value}
              class="input input-bordered w-full"
            />
          </div>
          <div class="flex justify-end gap-2">
            <button type="button" phx-click="cancel_form" class="btn btn-ghost">Cancel</button>
            <button type="submit" class="btn btn-primary" data-test="save-collection-btn">
              Save
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp collection_detail_view(assigns) do
    ~H"""
    <div class="flex items-center justify-between pb-4">
      <div class="flex items-center gap-3">
        <button phx-click="back_to_list" class="btn btn-ghost btn-sm">← Back</button>
        <.header>{@collection.title}</.header>
      </div>
      <button
        :if={@can_manage}
        phx-click="open_item_picker"
        class="btn btn-primary btn-sm"
        data-test="add-videos-btn"
      >
        Add Items
      </button>
    </div>

    <div :if={@collection.description} class="mb-4 text-base-content/70">
      {@collection.description}
    </div>

    <div :if={@items == []} class="py-8 text-center text-base-content/60">
      <p>No items in this collection yet.</p>
    </div>

    <div :if={@items != []} class="space-y-2">
      <div
        :for={item <- @items}
        class="flex items-center gap-3 p-3 bg-base-200 rounded-lg"
        data-test={item_test_id(item)}
      >
        <%= case item.item_type do %>
          <% :video -> %>
            <div class="w-20 h-12 rounded bg-base-300 overflow-hidden flex-shrink-0">
              <img
                :if={item.video && item.video.mux_playback_id}
                src={"https://image.mux.com/#{item.video.mux_playback_id}/thumbnail.webp?width=160&height=96"}
                alt={item.video && item.video.title}
                class="w-full h-full object-cover"
              />
            </div>
            <div class="flex-1 min-w-0">
              <div class="font-medium truncate">{item.video && item.video.title}</div>
            </div>
            <span class="badge badge-sm badge-ghost" data-test="type-badge">Video</span>
          <% :season -> %>
            <div class="w-20 h-12 rounded bg-base-300 overflow-hidden flex-shrink-0">
              <img
                :if={item.season && item.season.cover_image_url}
                src={item.season.cover_image_url}
                alt={item.season && item.season.title}
                class="w-full h-full object-cover"
              />
            </div>
            <div class="flex-1 min-w-0">
              <div class="font-medium truncate">{item.season && item.season.title}</div>
              <div class="text-xs text-base-content/60">
                {item.season && item.season.episode_count} episodes
              </div>
            </div>
            <span class="badge badge-sm badge-info" data-test="type-badge">Season</span>
          <% :series -> %>
            <div class="w-20 h-12 rounded bg-base-300 overflow-hidden flex-shrink-0">
              <img
                :if={item.series && item.series.cover_image_url}
                src={item.series.cover_image_url}
                alt={item.series && item.series.title}
                class="w-full h-full object-cover"
              />
            </div>
            <div class="flex-1 min-w-0">
              <div class="font-medium truncate">{item.series && item.series.title}</div>
            </div>
            <span class="badge badge-sm badge-primary" data-test="type-badge">Series</span>
        <% end %>

        <div :if={@can_manage} class="flex gap-1">
          <button
            phx-click="move_item_up"
            phx-value-item-id={item.id}
            class="btn btn-xs btn-ghost"
          >
            ↑
          </button>
          <button
            phx-click="move_item_down"
            phx-value-item-id={item.id}
            class="btn btn-xs btn-ghost"
          >
            ↓
          </button>
          <button
            phx-click="remove_item"
            phx-value-item-id={item.id}
            data-confirm="Remove item from collection?"
            class="btn btn-xs btn-outline btn-error"
            data-test={remove_test_id(item)}
          >
            Remove
          </button>
        </div>
      </div>
    </div>

    <.item_picker
      :if={@show_item_picker}
      picker_type={@picker_type}
      picker_videos={@picker_videos}
      picker_seasons={@picker_seasons}
      picker_series={@picker_series}
      selected_video_ids={@selected_video_ids}
    />
    """
  end

  defp item_picker(assigns) do
    assigns = assign(assigns, :selected_count, MapSet.size(assigns.selected_video_ids))

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div
        class="bg-base-100 rounded-lg p-6 w-full max-w-lg shadow-xl max-h-[80vh] flex flex-col"
        data-test="collection-item-picker"
      >
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold">Add Items</h3>
          <button
            phx-click="close_item_picker"
            class="btn btn-ghost btn-sm"
            aria-label="Close item picker"
          >
            ✕
          </button>
        </div>

        <div class="flex gap-1 mb-4" data-test="picker-type-tabs">
          <button
            phx-click="set_picker_type"
            phx-value-type="video"
            class={"btn btn-sm #{if @picker_type == :video, do: "btn-primary", else: "btn-ghost"}"}
            data-test="picker-type-video"
          >
            Videos
          </button>
          <button
            phx-click="set_picker_type"
            phx-value-type="season"
            class={"btn btn-sm #{if @picker_type == :season, do: "btn-primary", else: "btn-ghost"}"}
            data-test="picker-type-season"
          >
            Seasons
          </button>
          <button
            phx-click="set_picker_type"
            phx-value-type="series"
            class={"btn btn-sm #{if @picker_type == :series, do: "btn-primary", else: "btn-ghost"}"}
            data-test="picker-type-series"
          >
            Series
          </button>
        </div>

        <div class="space-y-2 overflow-y-auto flex-1" data-test="picker-results">
          <%= case @picker_type do %>
            <% :video -> %>
              <div
                :if={@picker_videos == []}
                class="py-4 text-center text-base-content/60"
              >
                All videos are already in this collection.
              </div>
              <div
                :for={video <- @picker_videos}
                class="flex items-center gap-3 p-2 bg-base-200 rounded"
              >
                <label class="flex items-center gap-3 cursor-pointer flex-1 min-w-0">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-primary"
                    checked={MapSet.member?(@selected_video_ids, video.id)}
                    phx-click="toggle_video_selection"
                    phx-value-video-id={video.id}
                    data-test={"select-video-#{video.id}"}
                  />
                  <span class="truncate">{video.title}</span>
                </label>
              </div>
            <% :season -> %>
              <div
                :if={@picker_seasons == []}
                class="py-4 text-center text-base-content/60"
              >
                No seasons available.
              </div>
              <div
                :for={season <- @picker_seasons}
                class="flex items-center gap-3 p-2 bg-base-200 rounded cursor-pointer hover:bg-base-300"
                phx-click="add_item_to_collection"
                phx-value-type="season"
                phx-value-id={season.id}
                data-test={"picker-item-season-#{season.id}"}
              >
                <div class="flex-1 min-w-0">
                  <span class="font-medium">{season.title}</span>
                  <span class="text-xs text-base-content/60 ml-2">
                    {season.episode_count} episodes
                  </span>
                </div>
                <span class="badge badge-sm badge-info">Season</span>
              </div>
            <% :series -> %>
              <div
                :if={@picker_series == []}
                class="py-4 text-center text-base-content/60"
              >
                No series available.
              </div>
              <div
                :for={series <- @picker_series}
                class="flex items-center gap-3 p-2 bg-base-200 rounded cursor-pointer hover:bg-base-300"
                phx-click="add_item_to_collection"
                phx-value-type="series"
                phx-value-id={series.id}
                data-test={"picker-item-series-#{series.id}"}
              >
                <div class="flex-1 min-w-0">
                  <span class="font-medium">{series.title}</span>
                </div>
                <span class="badge badge-sm badge-primary">Series</span>
              </div>
          <% end %>
        </div>

        <div
          :if={@picker_type == :video && @picker_videos != []}
          class="flex items-center justify-between mt-4 pt-4 border-t border-base-300"
        >
          <span class="text-sm text-base-content/60">
            {@selected_count} selected
          </span>
          <div class="flex gap-2">
            <button phx-click="close_item_picker" class="btn btn-ghost btn-sm">
              Cancel
            </button>
            <button
              phx-click="add_selected_videos"
              disabled={@selected_count == 0}
              class="btn btn-primary btn-sm"
              data-test="add-selected-videos-btn"
            >
              Add Selected
            </button>
          </div>
        </div>

        <div
          :if={@picker_type != :video}
          class="flex justify-end mt-4 pt-4 border-t border-base-300"
        >
          <button phx-click="close_item_picker" class="btn btn-ghost btn-sm">
            Close
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp load_collections(socket) do
    org = socket.assigns.organization
    %{results: collections} = Content.list_collections(org)
    assign(socket, :collections, collections)
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
