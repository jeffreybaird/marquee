defmodule BobineWeb.Admin.MembersLive do
  use BobineWeb, :live_view

  alias Bobine.Accounts
  alias Bobine.Viewers

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization

    {:ok,
     socket
     |> assign(:page_title, "Members")
     |> assign(:tab, "viewers")
     |> assign(:search, "")
     |> assign(:status_filter, nil)
     |> assign(:subscription_filter, nil)
     |> load_viewers(org)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> load_viewers(socket.assigns.organization)}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    status = if status == "", do: nil, else: String.to_existing_atom(status)

    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> load_viewers(socket.assigns.organization)}
  end

  @impl true
  def handle_event("filter_subscription", %{"subscription" => sub}, socket) do
    sub = if sub == "", do: nil, else: sub

    {:noreply,
     socket
     |> assign(:subscription_filter, sub)
     |> load_viewers(socket.assigns.organization)}
  end

  @impl true
  def handle_event("suspend_viewer", %{"id" => id}, socket) do
    with_viewer_action(socket, id, fn scope, viewer ->
      Viewers.suspend_viewer(scope, viewer)
    end)
  end

  @impl true
  def handle_event("ban_viewer", %{"id" => id}, socket) do
    with_viewer_action(socket, id, fn scope, viewer ->
      Viewers.ban_viewer(scope, viewer)
    end)
  end

  @impl true
  def handle_event("reactivate_viewer", %{"id" => id}, socket) do
    with_viewer_action(socket, id, fn scope, viewer ->
      Viewers.reactivate_viewer(scope, viewer)
    end)
  end

  @impl true
  def handle_event("grant_access", %{"id" => id}, socket) do
    with_viewer_action(socket, id, fn scope, viewer ->
      Viewers.grant_access(scope, viewer)
    end)
  end

  @impl true
  def handle_event("revoke_access", %{"id" => id}, socket) do
    with_viewer_action(socket, id, fn scope, viewer ->
      Viewers.revoke_access(scope, viewer)
    end)
  end

  defp with_viewer_action(socket, id, action_fn) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    if can_manage_viewers?(scope) do
      case Viewers.get_viewer(org, id) do
        {:ok, viewer} ->
          case action_fn.(scope, viewer) do
            {:ok, _} ->
              {:noreply,
               socket
               |> put_flash(:info, "Viewer updated.")
               |> load_viewers(org)}

            {:error, _, _} ->
              {:noreply, put_flash(socket, :error, "Could not update viewer.")}
          end

        {:error, :not_found} ->
          {:noreply, put_flash(socket, :error, "Viewer not found.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to manage viewers.")}
    end
  end

  defp load_viewers(socket, org) do
    opts = [
      search: socket.assigns.search,
      status: socket.assigns.status_filter,
      subscription_status: socket.assigns.subscription_filter,
      per_page: 25
    ]

    opts = Enum.reject(opts, fn {_, v} -> is_nil(v) or v == "" end)
    result = Viewers.list_viewers(org, opts)

    assign(socket, :viewers_page, result)
  end

  defp can_manage_viewers?(scope) do
    cond do
      scope.user.is_super_admin -> true
      # viewer_support's primary purpose is supporting viewers, so they can act.
      # editors can view but NOT act — they lack the viewer management capability.
      scope.membership && scope.membership.role in [:viewer_support, :admin, :owner] -> true
      true -> false
    end
  end

  defp can_view_viewers?(scope) do
    cond do
      scope.user.is_super_admin -> true
      # viewer_support, editor, admin, and owner can all view the viewer list
      scope.membership -> Accounts.role_at_least?(scope.membership, :viewer_support)
      true -> false
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :can_manage, can_manage_viewers?(assigns.current_scope))
    assigns = assign(assigns, :can_view, can_view_viewers?(assigns.current_scope))

    ~H"""
    <BobineWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <.header>Members</.header>

      <%!-- Tabs --%>
      <div class="mt-4 flex gap-2 border-b border-base-300">
        <button
          phx-click="switch_tab"
          phx-value-tab="team"
          class={"px-4 py-2 text-sm font-medium border-b-2 #{if @tab == "team", do: "border-primary text-primary", else: "border-transparent text-base-content/60 hover:text-base-content"}"}
        >
          Team
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="viewers"
          class={"px-4 py-2 text-sm font-medium border-b-2 #{if @tab == "viewers", do: "border-primary text-primary", else: "border-transparent text-base-content/60 hover:text-base-content"}"}
        >
          Viewers
        </button>
      </div>

      <%!-- Team tab --%>
      <div :if={@tab == "team"} class="mt-6">
        <p class="text-base-content/70">Team member management coming soon.</p>
      </div>

      <%!-- Viewers tab --%>
      <div :if={@tab == "viewers" && @can_view} class="mt-6">
        <%!-- Search and filters --%>
        <div class="flex flex-wrap gap-3 mb-4">
          <input
            type="text"
            placeholder="Search by email or name..."
            value={@search}
            phx-keyup="search"
            phx-key="Enter"
            phx-debounce="300"
            class="input input-sm input-bordered w-64"
            data-test="viewer-search"
          />
          <select
            phx-change="filter_status"
            name="status"
            class="select select-sm select-bordered"
            data-test="viewer-status-filter"
          >
            <option value="">All statuses</option>
            <option value="active" selected={@status_filter == :active}>Active</option>
            <option value="suspended" selected={@status_filter == :suspended}>Suspended</option>
            <option value="banned" selected={@status_filter == :banned}>Banned</option>
          </select>
          <select
            phx-change="filter_subscription"
            name="subscription"
            class="select select-sm select-bordered"
            data-test="viewer-subscription-filter"
          >
            <option value="">All subscriptions</option>
            <option value="active" selected={@subscription_filter == "active"}>Active</option>
            <option value="trial" selected={@subscription_filter == "trial"}>Trial</option>
            <option value="none" selected={@subscription_filter == "none"}>None</option>
            <option value="past_due" selected={@subscription_filter == "past_due"}>Past Due</option>
            <option value="canceled" selected={@subscription_filter == "canceled"}>Canceled</option>
          </select>
        </div>

        <%!-- Viewer list --%>
        <div data-test="viewer-list">
          <.table id="viewers-table" rows={@viewers_page.results}>
            <:col :let={viewer} label="Email">{viewer.email}</:col>
            <:col :let={viewer} label="Display Name">{viewer.display_name}</:col>
            <:col :let={viewer} label="Subscription">
              <span class={"badge badge-sm #{subscription_badge(viewer.subscription_status)}"}>
                {viewer.subscription_status}
              </span>
            </:col>
            <:col :let={viewer} label="Status">
              <span class={"badge badge-sm #{status_badge(viewer.status)}"}>
                {viewer.status}
              </span>
            </:col>
            <:col :let={viewer} label="Joined">
              {Calendar.strftime(viewer.inserted_at, "%b %d, %Y")}
            </:col>
            <:action :let={viewer}>
              <div class="flex gap-1" data-test={"viewer-row-#{viewer.id}"}>
                <.link
                  :if={@can_manage}
                  href={
                    ~p"/viewer-session/impersonate?#{%{viewer_id: viewer.id, return_path: ~p"/admin/members"}}"
                  }
                  method="post"
                  data-test={"impersonate-viewer-#{viewer.id}"}
                  class="btn btn-xs btn-ghost"
                >
                  View as
                </.link>
                <button
                  :if={@can_manage && viewer.status == :active}
                  phx-click="suspend_viewer"
                  phx-value-id={viewer.id}
                  class="btn btn-xs btn-warning btn-ghost"
                  data-test={"suspend-viewer-#{viewer.id}"}
                >
                  Suspend
                </button>
                <button
                  :if={@can_manage && viewer.status == :active}
                  phx-click="ban_viewer"
                  phx-value-id={viewer.id}
                  class="btn btn-xs btn-error btn-ghost"
                  data-test={"ban-viewer-#{viewer.id}"}
                >
                  Ban
                </button>
                <button
                  :if={@can_manage && viewer.status in [:suspended, :banned]}
                  phx-click="reactivate_viewer"
                  phx-value-id={viewer.id}
                  class="btn btn-xs btn-success btn-ghost"
                  data-test={"reactivate-viewer-#{viewer.id}"}
                >
                  Reactivate
                </button>
                <button
                  :if={@can_manage && viewer.subscription_status != "active"}
                  phx-click="grant_access"
                  phx-value-id={viewer.id}
                  class="btn btn-xs btn-info btn-ghost"
                  data-test={"grant-access-#{viewer.id}"}
                >
                  Grant
                </button>
                <button
                  :if={@can_manage && viewer.subscription_status == "active"}
                  phx-click="revoke_access"
                  phx-value-id={viewer.id}
                  class="btn btn-xs btn-ghost"
                  data-test={"revoke-access-#{viewer.id}"}
                >
                  Revoke
                </button>
              </div>
            </:action>
          </.table>

          <p
            :if={@viewers_page.results == []}
            class="text-center text-base-content/60 py-8"
          >
            No viewers found.
          </p>

          <div
            :if={@viewers_page.total_pages > 1}
            class="mt-4 text-sm text-base-content/60 text-center"
          >
            Page {@viewers_page.page} of {@viewers_page.total_pages} ({@viewers_page.total} viewers total)
          </div>
        </div>
      </div>

      <div :if={@tab == "viewers" && !@can_view} class="mt-6">
        <p class="text-base-content/70">You don't have permission to view viewers.</p>
      </div>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp subscription_badge("active"), do: "badge-success"
  defp subscription_badge("trial"), do: "badge-info"
  defp subscription_badge("past_due"), do: "badge-warning"
  defp subscription_badge("canceled"), do: "badge-error"
  defp subscription_badge(_), do: "badge-ghost"

  defp status_badge(:active), do: "badge-success"
  defp status_badge(:suspended), do: "badge-warning"
  defp status_badge(:banned), do: "badge-error"
  defp status_badge(_), do: "badge-ghost"
end
