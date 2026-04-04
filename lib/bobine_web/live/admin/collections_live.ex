defmodule BobineWeb.Admin.CollectionsLive do
  @moduledoc """
  Collection management. CRUD operations for content collections,
  video picker for assigning videos to collections, real-time updates
  via Events.

  Events: new_collection, edit_collection, save_collection, delete_collection,
          select_collection, add_video, remove_video
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
     |> assign(:show_video_picker, false)
     |> assign(:selected_collection, nil)
     |> assign(:collection_videos, [])
     |> assign(:available_videos, [])
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
        %{results: videos} = Content.list_collection_videos(org, collection)

        {:noreply,
         assign(socket,
           selected_collection: collection,
           collection_videos: videos
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
       collection_videos: [],
       show_video_picker: false,
       available_videos: []
     )}
  end

  @impl true
  def handle_event("open_video_picker", _params, socket) do
    org = socket.assigns.organization
    collection = socket.assigns.selected_collection
    %{results: all_videos} = Content.list_videos(org, per_page: 100)
    %{results: collection_videos} = Content.list_collection_videos(org, collection, per_page: 100)

    collection_video_ids = MapSet.new(collection_videos, & &1.id)
    available = Enum.reject(all_videos, &MapSet.member?(collection_video_ids, &1.id))

    {:noreply, assign(socket, show_video_picker: true, available_videos: available)}
  end

  @impl true
  def handle_event("close_video_picker", _params, socket) do
    {:noreply, assign(socket, show_video_picker: false, available_videos: [])}
  end

  @impl true
  def handle_event("add_video", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    collection = socket.assigns.selected_collection

    case Content.get_video(org, video_id) do
      {:ok, video} ->
        case Content.add_video_to_collection(scope, collection, video) do
          {:ok, _} ->
            %{results: videos} = Content.list_collection_videos(org, collection)

            {:noreply,
             socket
             |> assign(collection_videos: videos, show_video_picker: false, available_videos: [])
             |> put_flash(:info, "Video added to collection.")}

          {:error, :already_exists} ->
            {:noreply, put_flash(socket, :error, "Video already in collection.")}

          _ ->
            {:noreply, put_flash(socket, :error, "Failed to add video.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Video not found.")}
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
        %{results: videos} = Content.list_collection_videos(org, collection)

        {:noreply,
         socket
         |> assign(collection_videos: videos)
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
          videos={@collection_videos}
          can_manage={@can_manage}
          show_video_picker={@show_video_picker}
          available_videos={@available_videos}
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
        phx-click="open_video_picker"
        class="btn btn-primary btn-sm"
        data-test="add-videos-btn"
      >
        Add Videos
      </button>
    </div>

    <div :if={@collection.description} class="mb-4 text-base-content/70">
      {@collection.description}
    </div>

    <div :if={@videos == []} class="py-8 text-center text-base-content/60">
      <p>No videos in this collection yet.</p>
    </div>

    <div :if={@videos != []} class="space-y-2">
      <div
        :for={video <- @videos}
        class="flex items-center gap-3 p-3 bg-base-200 rounded-lg"
        data-test={"collection-video-#{video.id}"}
      >
        <div class="w-20 h-12 rounded bg-base-300 overflow-hidden flex-shrink-0">
          <img
            :if={video.mux_playback_id}
            src={"https://image.mux.com/#{video.mux_playback_id}/thumbnail.webp?width=160&height=96"}
            alt={video.title}
            class="w-full h-full object-cover"
          />
        </div>
        <div class="flex-1 min-w-0">
          <div class="font-medium truncate">{video.title}</div>
        </div>
        <div :if={@can_manage} class="flex gap-1">
          <button
            phx-click="move_video_up"
            phx-value-video-id={video.id}
            class="btn btn-xs btn-ghost"
          >
            ↑
          </button>
          <button
            phx-click="move_video_down"
            phx-value-video-id={video.id}
            class="btn btn-xs btn-ghost"
          >
            ↓
          </button>
          <button
            phx-click="remove_video"
            phx-value-video-id={video.id}
            data-confirm="Remove video from collection?"
            class="btn btn-xs btn-outline btn-error"
            data-test={"remove-video-#{video.id}"}
          >
            Remove
          </button>
        </div>
      </div>
    </div>

    <.video_picker
      :if={@show_video_picker}
      videos={@available_videos}
    />
    """
  end

  defp video_picker(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div class="bg-base-100 rounded-lg p-6 w-full max-w-lg shadow-xl max-h-[80vh] overflow-y-auto">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold">Add Videos</h3>
          <button phx-click="close_video_picker" class="btn btn-ghost btn-sm">✕</button>
        </div>

        <div :if={@videos == []} class="py-4 text-center text-base-content/60">
          All videos are already in this collection.
        </div>

        <div :if={@videos != []} class="space-y-2">
          <div
            :for={video <- @videos}
            class="flex items-center justify-between p-2 bg-base-200 rounded"
          >
            <span class="truncate">{video.title}</span>
            <button
              phx-click="add_video"
              phx-value-video-id={video.id}
              class="btn btn-xs btn-primary"
              data-test={"pick-video-#{video.id}"}
            >
              Add
            </button>
          </div>
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

  defp reorder_video_in_collection(socket, video_id, direction) do
    videos = socket.assigns.collection_videos
    index = Enum.find_index(videos, &(&1.id == video_id))

    new_index =
      case direction do
        :up -> max(0, index - 1)
        :down -> min(length(videos) - 1, index + 1)
      end

    if index != new_index do
      scope = socket.assigns.current_scope
      collection = socket.assigns.selected_collection
      reordered = swap(videos, index, new_index)
      ordered_ids = Enum.map(reordered, & &1.id)
      :ok = Content.reorder_collection_videos(scope, collection, ordered_ids)

      org = socket.assigns.organization
      %{results: videos} = Content.list_collection_videos(org, collection)
      {:noreply, assign(socket, collection_videos: videos)}
    else
      {:noreply, socket}
    end
  end

  defp swap(list, i, j) do
    list
    |> List.replace_at(i, Enum.at(list, j))
    |> List.replace_at(j, Enum.at(list, i))
  end

  defp error_messages(field) do
    Enum.map(field.errors, fn {msg, _opts} -> msg end)
  end

  defp field_error(assigns) do
    ~H"""
    <p class="text-error text-sm mt-1">{render_slot(@inner_block)}</p>
    """
  end
end
