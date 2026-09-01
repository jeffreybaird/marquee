defmodule MarqueeWeb.Super.AnalyticsLive do
  @moduledoc """
  Platform analytics dashboard for super admins.

  Shows platform overview cards, org health table (sortable, searchable,
  paginated), platform MRR chart, and org growth chart.

  Route: /super/analytics
  """

  use MarqueeWeb, :live_view

  alias Marquee.Admin

  @default_sort_by :name
  @default_sort_dir :asc
  @default_page 1
  @default_per_page 25
  @chart_days 30

  @impl true
  def mount(_params, _session, socket) do
    overview = Admin.platform_overview()
    to_date = Date.utc_today()
    from_date = Date.add(to_date, -@chart_days)
    mrr_series = Admin.list_daily_platform_mrr(from_date, to_date)
    signup_series = Admin.list_new_org_signups(from_date, to_date)

    socket =
      socket
      |> assign(:page_title, "Platform Analytics")
      |> assign(:current_path, "/super/analytics")
      |> assign(:current_user, socket.assigns.current_scope.user)
      |> assign(:overview, overview)
      |> assign(:mrr_series, mrr_series)
      |> assign(:signup_series, signup_series)
      |> assign(:search, "")
      |> assign(:sort_by, @default_sort_by)
      |> assign(:sort_dir, @default_sort_dir)
      |> assign(:page, @default_page)
      |> assign(:per_page, @default_per_page)
      |> load_org_health()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    socket =
      socket
      |> assign(:search, term)
      |> assign(:page, 1)
      |> load_org_health()

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort", %{"by" => by}, socket) do
    sort_by = String.to_existing_atom(by)

    {sort_by, sort_dir} =
      if socket.assigns.sort_by == sort_by do
        {sort_by, toggle_dir(socket.assigns.sort_dir)}
      else
        {sort_by, :asc}
      end

    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:sort_dir, sort_dir)
      |> assign(:page, 1)
      |> load_org_health()

    {:noreply, socket}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)

    socket =
      socket
      |> assign(:page, page)
      |> load_org_health()

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    if connected?(socket) do
      push_chart_events(socket)
    end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.SuperLayout.super_layout
      current_path={@current_path}
      current_user={@current_user}
      flash={@flash}
    >
      <.header>Platform Analytics</.header>

      <%!-- Overview cards --%>
      <div class="mt-8 grid grid-cols-2 gap-6 lg:grid-cols-4">
        <.stat_card
          label="Total Organizations"
          value={@overview.total_orgs}
          data_test="stat-total-orgs"
        />
        <.stat_card
          label="Total Viewers"
          value={@overview.total_viewers}
          data_test="stat-total-viewers"
        />
        <.stat_card
          label="Platform MRR"
          value={format_cents(@overview.platform_mrr_cents)}
          data_test="stat-platform-mrr"
        />
        <.stat_card
          label="Viewer Fee Revenue"
          value={format_cents(@overview.viewer_fee_revenue_cents)}
          data_test="stat-viewer-fee-revenue"
        />
      </div>

      <%!-- Charts --%>
      <div class="mt-10 grid grid-cols-1 gap-8 lg:grid-cols-2">
        <div class="rounded-lg border border-base-300 bg-base-200 p-6">
          <h2 class="text-base font-semibold text-base-content mb-4">Platform MRR (30 days)</h2>
          <canvas
            id="mrr-chart"
            phx-hook="AnalyticsChart"
            data-chart-event="super:mrr"
            data-test="mrr-chart"
            style="height: 240px;"
          />
        </div>

        <div class="rounded-lg border border-base-300 bg-base-200 p-6">
          <h2 class="text-base font-semibold text-base-content mb-4">New Orgs (30 days)</h2>
          <canvas
            id="signup-chart"
            phx-hook="AnalyticsChart"
            data-chart-event="super:signups"
            data-test="signup-chart"
            style="height: 240px;"
          />
        </div>
      </div>

      <%!-- Org health table --%>
      <div class="mt-10">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-base font-semibold text-base-content">Organization Health</h2>
          <.input
            type="text"
            name="search"
            value={@search}
            placeholder="Search organizations…"
            phx-change="search"
            phx-debounce="250"
            data-test="org-search"
          />
        </div>

        <div class="overflow-x-auto" data-test="org-health-table">
          <table class="table w-full">
            <thead>
              <tr>
                <.sort_header label="Name" sort_key="name" current={@sort_by} dir={@sort_dir} />
                <th>Plan</th>
                <.sort_header
                  label="Subscribers"
                  sort_key="subscribers"
                  current={@sort_by}
                  dir={@sort_dir}
                />
                <.sort_header label="MRR" sort_key="mrr" current={@sort_by} dir={@sort_dir} />
                <.sort_header
                  label="Videos"
                  sort_key="videos"
                  current={@sort_by}
                  dir={@sort_dir}
                />
                <th>Active Viewers (7d)</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={org <- @org_health.results}
                data-test={"org-health-row-#{org.id}"}
              >
                <td class="font-medium" data-test={"org-name-#{org.id}"}>{org.name}</td>
                <td class="text-sm text-base-content/70" data-test={"org-plan-#{org.id}"}>
                  {org.platform_plan_name || "—"}
                </td>
                <td data-test={"org-subscribers-#{org.id}"}>{org.subscriber_count}</td>
                <td data-test={"org-mrr-#{org.id}"}>{format_cents(org.mrr_cents)}</td>
                <td data-test={"org-videos-#{org.id}"}>{org.video_count}</td>
                <td data-test={"org-active-viewers-#{org.id}"}>{org.active_viewers_last_7d}</td>
                <td data-test={"org-status-#{org.id}"}>
                  <span class={status_badge_class(org.status)}>
                    {org.status || "none"}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>

          <p
            :if={@org_health.results == []}
            class="py-8 text-center text-base-content/60"
            data-test="org-health-empty"
          >
            No organizations found.
          </p>
        </div>

        <.pagination page={@org_health.page} total_pages={@org_health.total_pages} />
      </div>
    </MarqueeWeb.Components.SuperLayout.super_layout>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :data_test, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-200 p-6" data-test={@data_test}>
      <p class="text-sm text-base-content/60">{@label}</p>
      <p class="mt-1 text-3xl font-bold text-base-content">{@value}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :sort_key, :string, required: true
  attr :current, :atom, required: true
  attr :dir, :atom, required: true

  defp sort_header(assigns) do
    ~H"""
    <th>
      <button
        phx-click="sort"
        phx-value-by={@sort_key}
        class="flex items-center gap-1 font-semibold hover:text-primary"
        data-test={"sort-#{@sort_key}"}
        aria-label={"Sort by #{@label}"}
      >
        {@label}
        <span :if={@current == String.to_existing_atom(@sort_key)} class="text-xs">
          {if @dir == :asc, do: "↑", else: "↓"}
        </span>
      </button>
    </th>
    """
  end

  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true

  defp pagination(assigns) do
    ~H"""
    <div
      :if={@total_pages > 1}
      class="flex items-center justify-center gap-2 mt-6"
      data-test="pagination"
    >
      <button
        :if={@page > 1}
        phx-click="paginate"
        phx-value-page={@page - 1}
        class="btn btn-sm btn-ghost"
        data-test="pagination-prev"
        aria-label="Previous page"
      >
        Previous
      </button>

      <span class="text-sm text-base-content/70" data-test="pagination-info">
        Page {@page} of {@total_pages}
      </span>

      <button
        :if={@page < @total_pages}
        phx-click="paginate"
        phx-value-page={@page + 1}
        class="btn btn-sm btn-ghost"
        data-test="pagination-next"
        aria-label="Next page"
      >
        Next
      </button>
    </div>
    """
  end

  defp load_org_health(socket) do
    result =
      Admin.list_organizations_with_health(
        search: socket.assigns.search,
        sort_by: socket.assigns.sort_by,
        sort_dir: socket.assigns.sort_dir,
        page: socket.assigns.page,
        per_page: socket.assigns.per_page
      )

    assign(socket, :org_health, result)
  end

  defp push_chart_events(socket) do
    mrr_labels = Enum.map(socket.assigns.mrr_series, &Date.to_string(&1.date))
    mrr_data = Enum.map(socket.assigns.mrr_series, & &1.mrr_cents)

    signup_labels = Enum.map(socket.assigns.signup_series, &Date.to_string(&1.date))
    signup_data = Enum.map(socket.assigns.signup_series, & &1.count)

    socket
    |> push_event("super:mrr", %{labels: mrr_labels, data: mrr_data, type: "line"})
    |> push_event("super:signups", %{labels: signup_labels, data: signup_data, type: "line"})
  end

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  defp format_cents(nil), do: "$0"
  defp format_cents(0), do: "$0"

  defp format_cents(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    cents_rem = rem(cents, 100)
    "$#{dollars}.#{String.pad_leading("#{cents_rem}", 2, "0")}"
  end

  defp format_cents(val) do
    case Decimal.cast(val) do
      {:ok, d} -> d |> Decimal.round(0) |> Decimal.to_integer() |> format_cents()
      _ -> "$0"
    end
  end

  defp status_badge_class(:active), do: "badge badge-success badge-sm"
  defp status_badge_class(:trialing), do: "badge badge-info badge-sm"
  defp status_badge_class(:past_due), do: "badge badge-warning badge-sm"
  defp status_badge_class(_), do: "badge badge-ghost badge-sm"
end
