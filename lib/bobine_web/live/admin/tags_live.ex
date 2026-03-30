defmodule BobineWeb.Admin.TagsLive do
  use BobineWeb, :live_view

  alias Bobine.Content
  alias Bobine.Events

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
     |> assign(:page_title, "Tags")
     |> assign(:can_manage, can_manage)
     |> assign(:new_tag_name, "")
     |> assign(:editing_tag_id, nil)
     |> assign(:editing_tag_name, "")
     |> load_tags()}
  end

  @impl true
  def handle_event("create_tag", %{"name" => name}, socket) do
    name = String.trim(name)

    if name == "" do
      {:noreply, put_flash(socket, :error, "Tag name cannot be empty.")}
    else
      scope = socket.assigns.current_scope

      case Content.create_tag(scope, %{name: name}) do
        {:ok, _tag} ->
          {:noreply,
           socket
           |> assign(:new_tag_name, "")
           |> put_flash(:info, "Tag created.")
           |> load_tags()}

        {:error, :already_exists} ->
          {:noreply, put_flash(socket, :error, "A tag with this name already exists.")}

        {:error, :validation, _changeset} ->
          {:noreply, put_flash(socket, :error, "Invalid tag name.")}
      end
    end
  end

  @impl true
  def handle_event("update_new_tag", %{"name" => name}, socket) do
    {:noreply, assign(socket, :new_tag_name, name)}
  end

  @impl true
  def handle_event("start_edit", %{"id" => id, "name" => name}, socket) do
    {:noreply, assign(socket, editing_tag_id: id, editing_tag_name: name)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_tag_id: nil, editing_tag_name: "")}
  end

  @impl true
  def handle_event("update_editing_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :editing_tag_name, name)}
  end

  @impl true
  def handle_event("save_edit", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    name = String.trim(socket.assigns.editing_tag_name)

    if name == "" do
      {:noreply, put_flash(socket, :error, "Tag name cannot be empty.")}
    else
      case Content.get_tag(org, id) do
        {:ok, tag} ->
          case Content.update_tag(scope, tag, %{name: name, slug: Content.slugify(name)}) do
            {:ok, _} ->
              {:noreply,
               socket
               |> assign(editing_tag_id: nil, editing_tag_name: "")
               |> put_flash(:info, "Tag updated.")
               |> load_tags()}

            {:error, :validation, _} ->
              {:noreply, put_flash(socket, :error, "Failed to update tag.")}
          end

        {:error, :not_found} ->
          {:noreply, put_flash(socket, :error, "Tag not found.")}
      end
    end
  end

  @impl true
  def handle_event("delete_tag", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Content.get_tag(org, id) do
      {:ok, tag} ->
        {:ok, _} = Content.delete_tag(scope, tag)

        {:noreply,
         socket
         |> put_flash(:info, "Tag deleted.")
         |> load_tags()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Tag not found.")}
    end
  end

  @impl true
  def handle_info({:bobine_event, _event, _scope}, socket) do
    {:noreply, load_tags(socket)}
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
      <.header>Tags</.header>

      <div :if={@can_manage} class="mt-4 mb-6">
        <form phx-submit="create_tag" class="flex gap-2">
          <input
            type="text"
            name="name"
            value={@new_tag_name}
            phx-change="update_new_tag"
            placeholder="New tag name…"
            class="input input-bordered flex-1"
            data-test="new-tag-input"
          />
          <button type="submit" class="btn btn-primary" data-test="create-tag-btn">
            Add Tag
          </button>
        </form>
      </div>

      <div
        :if={@tags == []}
        class="py-12 text-center text-base-content/60"
        data-test="empty-state"
      >
        <p class="text-lg">No tags yet.</p>
        <p class="mt-2">Create your first tag to organize videos.</p>
      </div>

      <div :if={@tags != []} data-test="tags-list" class="space-y-2">
        <div
          :for={tag <- @tags}
          class="flex items-center justify-between p-3 bg-base-200 rounded-lg"
          data-test={"tag-#{tag.id}"}
        >
          <div :if={@editing_tag_id != tag.id} class="flex items-center gap-2">
            <span class="badge badge-lg">{tag.name}</span>
            <span class="text-xs text-base-content/50 font-mono">{tag.slug}</span>
          </div>

          <div :if={@editing_tag_id == tag.id} class="flex-1 flex gap-2 mr-2">
            <input
              type="text"
              value={@editing_tag_name}
              phx-change="update_editing_name"
              phx-keyup="update_editing_name"
              name="name"
              class="input input-bordered input-sm flex-1"
            />
            <button
              phx-click="save_edit"
              phx-value-id={tag.id}
              class="btn btn-xs btn-primary"
            >
              Save
            </button>
            <button phx-click="cancel_edit" class="btn btn-xs btn-ghost">Cancel</button>
          </div>

          <div :if={@can_manage && @editing_tag_id != tag.id} class="flex gap-1">
            <button
              phx-click="start_edit"
              phx-value-id={tag.id}
              phx-value-name={tag.name}
              class="btn btn-xs btn-outline"
            >
              Edit
            </button>
            <button
              phx-click="delete_tag"
              phx-value-id={tag.id}
              data-confirm="Delete this tag? It will be removed from all videos."
              class="btn btn-xs btn-outline btn-error"
              data-test={"delete-tag-#{tag.id}"}
            >
              Delete
            </button>
          </div>
        </div>
      </div>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp load_tags(socket) do
    org = socket.assigns.organization
    %{results: tags} = Content.list_tags(org)
    assign(socket, :tags, tags)
  end

  defp can_manage_content?(%{user: %{is_super_admin: true}}), do: true

  defp can_manage_content?(%{membership: %{role: role}}) when role in [:owner, :admin, :editor],
    do: true

  defp can_manage_content?(_), do: false
end
