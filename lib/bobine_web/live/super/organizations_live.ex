defmodule BobineWeb.Super.OrganizationsLive do
  use BobineWeb, :live_view

  alias Bobine.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Organizations")
     |> assign(:current_path, "/super/organizations")
     |> assign(:current_user, socket.assigns.current_scope.user)
     |> assign(:search, "")
     |> load_organizations("")}
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    {:noreply, load_organizations(socket, term) |> assign(:search, term)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <BobineWeb.Components.SuperLayout.super_layout
      current_path={@current_path}
      current_user={@current_user}
      flash={@flash}
    >
      <div class="flex items-center justify-between pb-4">
        <.header>Organizations</.header>
        <.link navigate={~p"/super/organizations/new"} data-test="new-org-btn">
          <.button>New Organization</.button>
        </.link>
      </div>

      <div class="mb-4">
        <.input
          type="text"
          name="search"
          value={@search}
          placeholder="Search by name or slug…"
          phx-change="search"
          phx-debounce="200"
          data-test="org-search"
        />
      </div>

      <div class="overflow-x-auto" data-test="org-table">
        <table class="table w-full">
          <thead>
            <tr>
              <th>Name</th>
              <th>Slug</th>
              <th>Custom Domain</th>
              <th>Members</th>
              <th>Videos</th>
              <th>Created</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={org <- @organizations} data-test={"org-row-#{org.id}"}>
              <td class="font-medium">{org.name}</td>
              <td class="text-base-content/70 font-mono text-sm">{org.slug}</td>
              <td class="text-base-content/70 text-sm">{org.custom_domain || "—"}</td>
              <td>{Admin.member_count(org)}</td>
              <td>{Admin.video_count(org)}</td>
              <td class="text-sm text-base-content/60">
                {Calendar.strftime(org.inserted_at, "%b %d, %Y")}
              </td>
              <td>
                <.link navigate={~p"/super/organizations/#{org.id}"} class="link">
                  View
                </.link>
              </td>
            </tr>
          </tbody>
        </table>

        <p
          :if={@organizations == []}
          class="py-8 text-center text-base-content/60"
          data-test="empty-state"
        >
          No organizations found.
        </p>
      </div>
    </BobineWeb.Components.SuperLayout.super_layout>
    """
  end

  defp load_organizations(socket, search) do
    orgs = Admin.list_organizations(search: search)
    assign(socket, :organizations, orgs)
  end
end
