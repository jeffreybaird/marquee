# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule MarqueeWeb.Admin.MembersLive do
  @moduledoc """
  Member management with two tabs: viewers and operators. Supports search,
  status/subscription filtering for viewers, and viewer impersonation.

  Events: switch_tab, search, filter, page,
          suspend_viewer, ban_viewer, reactivate_viewer, grant_access, revoke_access
  Route: /admin/members
  """

  use MarqueeWeb, :live_view

  alias Marquee.Accounts
  alias Marquee.Viewers

  @per_page 25

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
     |> assign(:page, 1)
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
     |> assign(:page, 1)
     |> load_viewers(socket.assigns.organization)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    status =
      case params["status"] do
        "" -> nil
        nil -> socket.assigns.status_filter
        s -> String.to_existing_atom(s)
      end

    subscription =
      case params["subscription"] do
        "" -> nil
        nil -> socket.assigns.subscription_filter
        s -> s
      end

    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> assign(:subscription_filter, subscription)
     |> assign(:page, 1)
     |> load_viewers(socket.assigns.organization)}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(:page, String.to_integer(page))
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

    case Viewers.get_viewer(org, id) do
      {:ok, viewer} ->
        case action_fn.(scope, viewer) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Viewer updated.")
             |> load_viewers(org)}

          {:error, :forbidden} ->
            {:noreply, put_flash(socket, :error, "You don't have permission to manage viewers.")}

          {:error, _, _} ->
            {:noreply, put_flash(socket, :error, "Could not update viewer.")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Viewer not found.")}
    end
  end

  defp load_viewers(socket, org) do
    opts = [
      search: socket.assigns.search,
      status: socket.assigns.status_filter,
      subscription_status: socket.assigns.subscription_filter,
      page: socket.assigns.page,
      per_page: @per_page
    ]

    opts = Enum.reject(opts, fn {_, v} -> is_nil(v) or v == "" end)
    result = Viewers.list_viewers(org, opts)

    assign(socket, :viewers_page, result)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :can_manage, Accounts.can_manage_viewers?(assigns.current_scope))
    assigns = assign(assigns, :can_view, Accounts.can_view_viewers?(assigns.current_scope))

    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <.header>Members</.header>

      <%!-- Tabs --%>
      <div class="mt-4 flex gap-2 border-b border-admin-border">
        <button
          phx-click="switch_tab"
          phx-value-tab="team"
          class={"px-4 py-2 text-sm font-medium border-b-2 #{if @tab == "team", do: "border-admin-accent text-admin-accent", else: "border-transparent text-admin-muted hover:text-admin-fg"}"}
        >
          Team
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="viewers"
          class={"px-4 py-2 text-sm font-medium border-b-2 #{if @tab == "viewers", do: "border-admin-accent text-admin-accent", else: "border-transparent text-admin-muted hover:text-admin-fg"}"}
        >
          Viewers
        </button>
      </div>

      <%!-- Team tab --%>
      <div :if={@tab == "team"} class="mt-6">
        <p class="text-admin-muted">Team member management coming soon.</p>
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
            class="w-64 rounded-md border border-admin-border bg-admin-card px-3 py-1.5 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
            data-test="viewer-search"
          />
          <form phx-change="filter" class="flex flex-wrap gap-3">
            <select
              name="status"
              class="w-auto rounded-md border border-admin-border bg-admin-card px-3 py-1.5 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
              data-test="viewer-status-filter"
            >
              <option value="">All statuses</option>
              <option value="active" selected={@status_filter == :active}>Active</option>
              <option value="suspended" selected={@status_filter == :suspended}>Suspended</option>
              <option value="banned" selected={@status_filter == :banned}>Banned</option>
            </select>
            <select
              name="subscription"
              class="w-auto rounded-md border border-admin-border bg-admin-card px-3 py-1.5 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
              data-test="viewer-subscription-filter"
            >
              <option value="">All subscriptions</option>
              <option value="active" selected={@subscription_filter == "active"}>Active</option>
              <option value="trial" selected={@subscription_filter == "trial"}>Trial</option>
              <option value="none" selected={@subscription_filter == "none"}>None</option>
              <option value="past_due" selected={@subscription_filter == "past_due"}>Past Due</option>
              <option value="canceled" selected={@subscription_filter == "canceled"}>Canceled</option>
            </select>
          </form>
        </div>

        <%!-- Viewer list --%>
        <div data-test="viewer-list">
          <.table id="viewers-table" rows={@viewers_page.results}>
            <:col :let={viewer} label="Email">{viewer.email}</:col>
            <:col :let={viewer} label="Display Name">{viewer.display_name}</:col>
            <:col :let={viewer} label="Subscription">
              <span class={"rounded-full px-2 py-0.5 font-ui text-xs #{subscription_badge(viewer.subscription_status)}"}>
                {viewer.subscription_status}
              </span>
            </:col>
            <:col :let={viewer} label="Status">
              <span class={"rounded-full px-2 py-0.5 font-ui text-xs #{status_badge(viewer.status)}"}>
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
                  class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
                >
                  View as
                </.link>
                <button
                  :if={@can_manage && viewer.status == :active}
                  phx-click="suspend_viewer"
                  phx-value-id={viewer.id}
                  class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-warning hover:bg-admin-card"
                  data-test={"suspend-viewer-#{viewer.id}"}
                >
                  Suspend
                </button>
                <button
                  :if={@can_manage && viewer.status == :active}
                  phx-click="ban_viewer"
                  phx-value-id={viewer.id}
                  class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-error hover:bg-admin-card"
                  data-test={"ban-viewer-#{viewer.id}"}
                >
                  Ban
                </button>
                <button
                  :if={@can_manage && viewer.status in [:suspended, :banned]}
                  phx-click="reactivate_viewer"
                  phx-value-id={viewer.id}
                  class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-success hover:bg-admin-card"
                  data-test={"reactivate-viewer-#{viewer.id}"}
                >
                  Reactivate
                </button>
                <button
                  :if={@can_manage && viewer.subscription_status != "active"}
                  phx-click="grant_access"
                  phx-value-id={viewer.id}
                  class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-info hover:bg-admin-card"
                  data-test={"grant-access-#{viewer.id}"}
                >
                  Grant
                </button>
                <button
                  :if={@can_manage && viewer.subscription_status == "active"}
                  phx-click="revoke_access"
                  phx-value-id={viewer.id}
                  class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
                  data-test={"revoke-access-#{viewer.id}"}
                >
                  Revoke
                </button>
              </div>
            </:action>
          </.table>

          <p
            :if={@viewers_page.results == []}
            class="text-center text-admin-muted py-8"
          >
            No viewers found.
          </p>

          <nav
            :if={@viewers_page.total_pages > 1}
            class="mt-4 flex items-center justify-between"
            aria-label="Pagination"
            data-test="viewer-pagination"
          >
            <span class="text-sm text-admin-muted">
              Page {@viewers_page.page} of {@viewers_page.total_pages} ({@viewers_page.total} viewers)
            </span>
            <div class="flex gap-2">
              <button
                phx-click="page"
                phx-value-page={@viewers_page.page - 1}
                disabled={@viewers_page.page <= 1}
                class="rounded-md border border-admin-border px-3 py-1.5 font-ui text-sm text-admin-fg hover:bg-admin-card disabled:opacity-50 disabled:cursor-not-allowed"
                data-test="viewer-prev-page"
              >
                Previous
              </button>
              <button
                phx-click="page"
                phx-value-page={@viewers_page.page + 1}
                disabled={@viewers_page.page >= @viewers_page.total_pages}
                class="rounded-md border border-admin-border px-3 py-1.5 font-ui text-sm text-admin-fg hover:bg-admin-card disabled:opacity-50 disabled:cursor-not-allowed"
                data-test="viewer-next-page"
              >
                Next
              </button>
            </div>
          </nav>
        </div>
      </div>

      <div :if={@tab == "viewers" && !@can_view} class="mt-6">
        <p class="text-admin-muted">You don't have permission to view viewers.</p>
      </div>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp subscription_badge("active"), do: "border border-success/40 bg-success/10 text-success"
  defp subscription_badge("trial"), do: "border border-info/40 bg-info/10 text-admin-fg"
  defp subscription_badge("past_due"), do: "border border-warning/40 bg-warning/10 text-warning"
  defp subscription_badge("canceled"), do: "border border-error/40 bg-error/10 text-error"
  defp subscription_badge(_), do: "bg-admin-card text-admin-muted"

  defp status_badge(:active), do: "border border-success/40 bg-success/10 text-success"
  defp status_badge(:suspended), do: "border border-warning/40 bg-warning/10 text-warning"
  defp status_badge(:banned), do: "border border-error/40 bg-error/10 text-error"
  defp status_badge(_), do: "bg-admin-card text-admin-muted"
end
