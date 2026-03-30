defmodule BobineWeb.Admin.CatalogLive do
  use BobineWeb, :live_view

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

    can_manage = can_manage_content?(scope)

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
     |> load_rows()}
  end

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
        {:noreply, load_rows(socket)}

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

  # Curated row video management
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

  @impl true
  def handle_info({:bobine_event, _event, _scope}, socket) do
    {:noreply, load_rows(socket)}
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
      <%= if @selected_row && @row_videos != [] || (@selected_row && @selected_row.source_type == :curated && @preview_videos == []) do %>
        <.row_items_view
          row={@selected_row}
          videos={@row_videos}
          can_manage={@can_manage}
          show_video_picker={@show_video_picker}
          available_videos={@available_videos}
        />
      <% else %>
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

  defp rows_list_view(assigns) do
    ~H"""
    <div class="flex items-center justify-between pb-4">
      <.header>Catalog</.header>
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
              >
                ↑
              </button>
              <button
                :if={@can_manage}
                phx-click="move_down"
                phx-value-id={row.id}
                class="btn btn-xs btn-ghost"
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
            <label class="label">Collection</label>
            <select
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
            <label class="label">Tag</label>
            <select
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
          <button phx-click="close_preview" class="btn btn-ghost btn-sm">✕</button>
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
          <button phx-click="close_video_picker" class="btn btn-ghost btn-sm">✕</button>
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

  defp load_rows(socket) do
    org = socket.assigns.organization
    %{results: rows} = Catalog.list_rows(org)
    assign(socket, :rows, rows)
  end

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

  defp swap(list, i, j) do
    list
    |> List.replace_at(i, Enum.at(list, j))
    |> List.replace_at(j, Enum.at(list, i))
  end

  defp source_type_label(:curated), do: "Curated"
  defp source_type_label(:collection), do: "Collection"
  defp source_type_label(:tag), do: "Tag"
  defp source_type_label(:recent), do: "Recent"
  defp source_type_label(:popular), do: "Popular"
  defp source_type_label(:continue_watching), do: "Continue Watching"
  defp source_type_label(other), do: to_string(other)

  defp show_source_select?(current, target) do
    to_string(current) == to_string(target)
  end

  defp can_manage_content?(%{user: %{is_super_admin: true}}), do: true

  defp can_manage_content?(%{membership: %{role: role}}) when role in [:owner, :admin, :editor],
    do: true

  defp can_manage_content?(_), do: false
end
