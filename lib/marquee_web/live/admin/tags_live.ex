# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule MarqueeWeb.Admin.TagsLive do
  @moduledoc """
  Tag management. CRUD operations for content tags with real-time
  updates via Events.

  Events: new_tag, edit_tag, save_tag, delete_tag
  Route: /admin/tags
  """

  use MarqueeWeb, :live_view

  alias Marquee.Accounts
  alias Marquee.Content
  alias Marquee.Events

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
  # credo:disable-for-next-line Credo.Check.Refactor.Nesting
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
  def handle_info({:marquee_event, _event, _scope}, socket) do
    {:noreply, load_tags(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      trial_status={@trial_status}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <MarqueeWeb.Components.AdminUI.admin_panel
        title="Tags"
        subtitle="Organize videos with reusable labels."
      >
        <form :if={@can_manage} phx-submit="create_tag" class="flex gap-2">
          <input
            type="text"
            name="name"
            value={@new_tag_name}
            phx-change="update_new_tag"
            placeholder="New tag name…"
            class="flex-1 rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
            data-test="new-tag-input"
          />
          <MarqueeWeb.Components.AdminUI.admin_button
            type="submit"
            size={:sm}
            data-test="create-tag-btn"
          >
            Add Tag
          </MarqueeWeb.Components.AdminUI.admin_button>
        </form>

        <MarqueeWeb.Components.AdminUI.admin_empty
          :if={@tags == []}
          title="No tags yet"
          description="Create your first tag to organize videos."
          data_test="empty-state"
        />

        <div :if={@tags != []} data-test="tags-list" class="space-y-2">
          <div
            :for={tag <- @tags}
            class="flex items-center justify-between rounded-lg border border-admin-border bg-admin-card p-3"
            data-test={"tag-#{tag.id}"}
          >
            <div :if={@editing_tag_id != tag.id} class="flex items-center gap-3">
              <span class="rounded-full border border-admin-border bg-admin-card px-3 py-1 font-ui text-sm font-medium text-admin-fg">
                {tag.name}
              </span>
              <span class="font-mono text-xs text-admin-muted">{tag.slug}</span>
            </div>

            <div :if={@editing_tag_id == tag.id} class="flex flex-1 gap-2 mr-2">
              <input
                type="text"
                value={@editing_tag_name}
                phx-change="update_editing_name"
                phx-keyup="update_editing_name"
                name="name"
                class="flex-1 rounded-md border border-admin-border bg-admin-card px-3 py-1.5 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
              />
              <MarqueeWeb.Components.AdminUI.admin_button
                size={:sm}
                phx-click="save_edit"
                phx-value-id={tag.id}
              >
                Save
              </MarqueeWeb.Components.AdminUI.admin_button>
              <MarqueeWeb.Components.AdminUI.admin_button
                variant={:ghost}
                size={:sm}
                phx-click="cancel_edit"
              >
                Cancel
              </MarqueeWeb.Components.AdminUI.admin_button>
            </div>

            <div :if={@can_manage && @editing_tag_id != tag.id} class="flex gap-1">
              <MarqueeWeb.Components.AdminUI.admin_button
                variant={:ghost}
                size={:sm}
                phx-click="start_edit"
                phx-value-id={tag.id}
                phx-value-name={tag.name}
              >
                Edit
              </MarqueeWeb.Components.AdminUI.admin_button>
              <MarqueeWeb.Components.AdminUI.admin_button
                variant={:danger}
                size={:sm}
                phx-click="delete_tag"
                phx-value-id={tag.id}
                data-confirm="Delete this tag? It will be removed from all videos."
                data-test={"delete-tag-#{tag.id}"}
              >
                Delete
              </MarqueeWeb.Components.AdminUI.admin_button>
            </div>
          </div>
        </div>
      </MarqueeWeb.Components.AdminUI.admin_panel>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp load_tags(socket) do
    org = socket.assigns.organization
    %{results: tags} = Content.list_tags(org)
    assign(socket, :tags, tags)
  end
end
