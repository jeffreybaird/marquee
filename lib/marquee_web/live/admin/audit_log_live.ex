defmodule MarqueeWeb.Admin.AuditLogLive do
  @moduledoc """
  Audit log explorer for operators. Lists audit events scoped to the current
  organization with filtering, expandable rows, cursor-based load-more, and
  CSV export via a background job.

  Route: /admin/audit-log
  """

  use MarqueeWeb, :live_view

  alias Marquee.Audit
  alias Marquee.Workers.AuditLogExporter

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    current_user = socket.assigns.current_scope.user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Marquee.PubSub, "audit-exports:#{current_user.id}")
    end

    filter_options = Audit.get_filter_options(org)
    %{results: logs, next_cursor: next_cursor} = Audit.list_for_organization(org)

    {:ok,
     socket
     |> assign(:page_title, "Audit Log")
     |> assign(:current_user, current_user)
     |> assign(:filter_options, filter_options)
     |> assign(:logs, logs)
     |> assign(:next_cursor, next_cursor)
     |> assign(:expanded_ids, MapSet.new())
     |> assign(:filters, %{})}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = build_filters(params)
    org = socket.assigns.organization
    %{results: logs, next_cursor: next_cursor} = Audit.list_for_organization(org, filters)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:logs, logs)
     |> assign(:next_cursor, next_cursor)
     |> assign(:expanded_ids, MapSet.new())}
  end

  @impl true
  def handle_event("filter_by_actor", %{"user_id" => user_id}, socket) do
    filters = Map.put(socket.assigns.filters, :user_id, user_id)
    org = socket.assigns.organization
    %{results: logs, next_cursor: next_cursor} = Audit.list_for_organization(org, filters)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:logs, logs)
     |> assign(:next_cursor, next_cursor)
     |> assign(:expanded_ids, MapSet.new())}
  end

  @impl true
  def handle_event("filter_by_action", %{"action" => action}, socket) do
    filters = Map.put(socket.assigns.filters, :action, action)
    org = socket.assigns.organization
    %{results: logs, next_cursor: next_cursor} = Audit.list_for_organization(org, filters)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:logs, logs)
     |> assign(:next_cursor, next_cursor)
     |> assign(:expanded_ids, MapSet.new())}
  end

  @impl true
  def handle_event("load_more", _params, %{assigns: %{next_cursor: nil}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    org = socket.assigns.organization
    filters = socket.assigns.filters
    cursor = socket.assigns.next_cursor

    %{results: new_logs, next_cursor: next_cursor} =
      Audit.list_for_organization(org, filters, cursor: cursor)

    {:noreply,
     socket
     |> update(:logs, &(&1 ++ new_logs))
     |> assign(:next_cursor, next_cursor)}
  end

  @impl true
  def handle_event("toggle_expand", %{"id" => id}, socket) do
    expanded_ids =
      if MapSet.member?(socket.assigns.expanded_ids, id) do
        MapSet.delete(socket.assigns.expanded_ids, id)
      else
        MapSet.put(socket.assigns.expanded_ids, id)
      end

    {:noreply, assign(socket, :expanded_ids, expanded_ids)}
  end

  @impl true
  def handle_event("export_csv", _params, socket) do
    org = socket.assigns.organization
    current_user = socket.assigns.current_user
    filters = socket.assigns.filters

    %{}
    |> Map.put("organization_id", org.id)
    |> Map.put("scope", "org")
    |> Map.put("filters", stringify_filters(filters))
    |> Map.put("user_id", current_user.id)
    |> Map.put("format", "csv")
    |> Marquee.Otel.put_trace_context()
    |> AuditLogExporter.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Export queued. You'll be notified when ready.")}
  end

  @impl true
  def handle_info({:audit_export_ready, url}, socket) do
    {:noreply, put_flash(socket, :info, "Export ready. Download: #{url}")}
  end

  @impl true
  def handle_info({:audit_export_failed, _reason}, socket) do
    {:noreply, put_flash(socket, :error, "Export failed. Please try again.")}
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
      flash={@flash}
    >
      <.header>
        Audit Log
        <:actions>
          <button
            phx-click="export_csv"
            class="inline-flex items-center gap-1.5 rounded-md border border-admin-border bg-admin-card px-3 py-1.5 font-ui text-sm font-medium text-admin-fg hover:border-admin-border"
            data-test="export-csv-btn"
          >
            Export CSV
          </button>
        </:actions>
      </.header>

      <div class="mt-6 space-y-4">
        <.filter_bar
          filter_options={@filter_options}
          filters={@filters}
        />

        <div class="overflow-x-auto rounded-lg border border-admin-border">
          <table class="table w-full text-sm" data-test="audit-log-table">
            <thead>
              <tr class="border-b border-admin-border bg-admin-bg">
                <th class="px-4 py-3 text-left font-medium">Timestamp</th>
                <th class="px-4 py-3 text-left font-medium">Actor</th>
                <th class="px-4 py-3 text-left font-medium">Action</th>
                <th class="px-4 py-3 text-left font-medium">Resource</th>
                <th class="px-4 py-3 text-left font-medium">Details</th>
              </tr>
            </thead>
            <tbody>
              <.log_row
                :for={log <- @logs}
                log={log}
                expanded={MapSet.member?(@expanded_ids, log.id)}
              />
              <tr :if={@logs == []}>
                <td
                  colspan="5"
                  class="px-4 py-8 text-center text-admin-muted"
                  data-test="empty-state"
                >
                  No audit events found.
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@next_cursor} class="flex justify-center mt-4">
          <button
            phx-click="load_more"
            class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
            data-test="load-more-btn"
          >
            Load more
          </button>
        </div>
      </div>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end

  attr :filter_options, :map, required: true
  attr :filters, :map, required: true

  defp filter_bar(assigns) do
    ~H"""
    <form phx-change="filter" phx-submit="filter" class="flex flex-wrap gap-3 items-end">
      <div>
        <label class="text-xs font-medium text-admin-muted block mb-1" for="filter-action">
          Action
        </label>
        <select
          id="filter-action"
          name="action"
          class="w-auto rounded-md border border-admin-border bg-admin-card px-3 py-1.5 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
          data-test="filter-action"
        >
          <option value="">All actions</option>
          <option :for={a <- @filter_options.actions} value={a} selected={@filters[:action] == a}>
            {a}
          </option>
        </select>
      </div>

      <div>
        <label class="text-xs font-medium text-admin-muted block mb-1" for="filter-actor">
          Actor
        </label>
        <select
          id="filter-actor"
          name="user_id"
          class="w-auto rounded-md border border-admin-border bg-admin-card px-3 py-1.5 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
          data-test="filter-actor"
        >
          <option value="">All actors</option>
          <option
            :for={u <- @filter_options.actors}
            value={u.id}
            selected={@filters[:user_id] == u.id}
          >
            {u.email}
          </option>
        </select>
      </div>

      <div>
        <label class="text-xs font-medium text-admin-muted block mb-1" for="filter-resource-type">
          Resource Type
        </label>
        <select
          id="filter-resource-type"
          name="resource_type"
          class="w-auto rounded-md border border-admin-border bg-admin-card px-3 py-1.5 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
          data-test="filter-resource-type"
        >
          <option value="">All types</option>
          <option
            :for={rt <- @filter_options.resource_types}
            value={rt}
            selected={@filters[:resource_type] == rt}
          >
            {rt}
          </option>
        </select>
      </div>

      <div>
        <label class="text-xs font-medium text-admin-muted block mb-1" for="filter-from">
          From
        </label>
        <input
          id="filter-from"
          type="date"
          name="from"
          class="rounded-md border border-admin-border bg-admin-card px-3 py-1.5 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
          value={@filters[:from]}
          data-test="filter-from"
        />
      </div>

      <div>
        <label class="text-xs font-medium text-admin-muted block mb-1" for="filter-to">
          To
        </label>
        <input
          id="filter-to"
          type="date"
          name="to"
          class="rounded-md border border-admin-border bg-admin-card px-3 py-1.5 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
          value={@filters[:to]}
          data-test="filter-to"
        />
      </div>

      <div class="flex-1 min-w-40">
        <label class="text-xs font-medium text-admin-muted block mb-1" for="filter-search">
          Search
        </label>
        <input
          id="filter-search"
          type="text"
          name="search"
          class="rounded-md border border-admin-border bg-admin-card px-3 py-1.5 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none w-full"
          placeholder="Search actions or resource ID..."
          value={@filters[:search]}
          data-test="filter-search"
        />
      </div>
    </form>
    """
  end

  attr :log, :any, required: true
  attr :expanded, :boolean, required: true

  defp log_row(assigns) do
    ~H"""
    <tr
      class="border-b border-admin-border hover:bg-admin-card/50"
      data-test={"audit-log-row-#{@log.id}"}
    >
      <td class="px-4 py-3 whitespace-nowrap text-xs text-admin-muted">
        {format_timestamp(@log.inserted_at)}
      </td>
      <td class="px-4 py-3">
        <span :if={@log.user}>
          <button
            phx-click="filter_by_actor"
            phx-value-user_id={@log.user_id}
            class="text-admin-accent hover:underline text-sm"
            data-test={"actor-link-#{@log.id}"}
          >
            {@log.user.email}
          </button>
        </span>
        <span :if={!@log.user} class="text-admin-muted text-xs">system</span>
      </td>
      <td class="px-4 py-3">
        <button
          phx-click="filter_by_action"
          phx-value-action={@log.action}
          class="font-mono text-xs bg-admin-card px-2 py-0.5 rounded hover:opacity-80"
          data-test={"action-link-#{@log.id}"}
        >
          {@log.action}
        </button>
      </td>
      <td class="px-4 py-3 text-xs">
        <span class="font-medium">{@log.resource_type}</span>
        <span :if={@log.resource_id} class="text-admin-muted ml-1">
          {short_id(@log.resource_id)}
        </span>
      </td>
      <td class="px-4 py-3">
        <button
          phx-click="toggle_expand"
          phx-value-id={@log.id}
          class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
          aria-label={if @expanded, do: "Collapse metadata", else: "Expand metadata"}
          data-test={"expand-btn-#{@log.id}"}
        >
          {if @expanded, do: "Hide", else: "Show"}
        </button>
      </td>
    </tr>
    <tr :if={@expanded} data-test={"metadata-row-#{@log.id}"}>
      <td colspan="5" class="px-4 py-3 bg-admin-bg">
        <pre class="text-xs overflow-x-auto whitespace-pre-wrap break-all">
          {Jason.encode!(@log.metadata, pretty: true)}
        </pre>
      </td>
    </tr>
    """
  end

  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_timestamp(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_timestamp(nil), do: ""

  defp short_id(id) when is_binary(id) do
    String.slice(id, 0, 8) <> "..."
  end

  defp short_id(_), do: ""

  defp build_filters(params) do
    %{}
    |> maybe_put(:action, params["action"])
    |> maybe_put(:user_id, params["user_id"])
    |> maybe_put(:resource_type, params["resource_type"])
    |> maybe_put(:from, parse_date(params["from"]))
    |> maybe_put(:to, parse_date(params["to"]))
    |> maybe_put(:search, params["search"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp stringify_filters(filters) do
    filters
    |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
    |> Map.new()
  end
end
