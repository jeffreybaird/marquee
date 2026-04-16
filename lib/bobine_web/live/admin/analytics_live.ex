defmodule BobineWeb.Admin.AnalyticsLive do
  @moduledoc """
  Operator analytics dashboard.

  Displays KPI cards, subscriber/revenue charts, content performance table,
  engagement metrics, and churn indicators. Period-selectable from 7/30/90 days.

  Route: /admin/analytics
  """

  use BobineWeb, :live_view

  alias Bobine.Analytics
  alias Bobine.Content

  @default_period "30"

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    period = @default_period

    socket =
      socket
      |> assign(page_title: "Analytics")
      |> assign(period: period)
      |> assign(sort_by: :unique_viewers)
      |> assign(sort_dir: :desc)
      |> assign(content_page: 1)
      |> load_all_data(org, period)

    {:ok, socket}
  end

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) do
    org = socket.assigns.organization

    socket =
      socket
      |> assign(period: period, content_page: 1)
      |> load_all_data(org, period)

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort_content", %{"col" => col}, socket) do
    col_atom = String.to_existing_atom(col)
    org = socket.assigns.organization

    {sort_by, sort_dir} =
      if socket.assigns.sort_by == col_atom do
        {col_atom, toggle_dir(socket.assigns.sort_dir)}
      else
        {col_atom, :desc}
      end

    content =
      Analytics.list_content_performance(org, socket.assigns.period,
        sort_by: sort_by,
        sort_dir: sort_dir,
        page: 1,
        per_page: 20
      )

    socket =
      socket
      |> assign(sort_by: sort_by, sort_dir: sort_dir, content_page: 1)
      |> assign(content_performance: content)

    {:noreply, socket}
  end

  @impl true
  def handle_event("content_page", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    org = socket.assigns.organization

    content =
      Analytics.list_content_performance(org, socket.assigns.period,
        sort_by: socket.assigns.sort_by,
        sort_dir: socket.assigns.sort_dir,
        page: page,
        per_page: 20
      )

    {:noreply, assign(socket, content_performance: content, content_page: page)}
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
      <div class="space-y-8">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <.header>Analytics</.header>

          <div class="flex gap-2" role="group" aria-label="Period selector">
            <button
              :for={days <- ["7", "30", "90"]}
              phx-click="set_period"
              phx-value-period={days}
              data-test={"period-selector-#{days}"}
              class={period_btn_class(@period, days)}
              aria-pressed={@period == days}
            >
              {days}d
            </button>
          </div>
        </div>

        <%!-- Overview KPI cards --%>
        <section aria-label="Overview" class="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <.kpi_card
            label="Active Subscribers"
            value={@overview.active_subscribers}
            data_test="kpi-active-subscribers"
          />
          <.kpi_card
            label="MRR"
            value={"$#{format_cents(@overview.mrr_cents)}"}
            data_test="kpi-mrr"
          />
          <.kpi_card
            label="Total Views"
            value={@overview.total_views}
            data_test="kpi-total-views"
          />
          <.kpi_card
            label="Avg Watch Time"
            value={format_seconds(@overview.avg_watch_time_seconds)}
            data_test="kpi-avg-watch-time"
          />
        </section>

        <%!-- Subscriber chart --%>
        <section aria-label="Subscriber trend">
          <h2 class="text-lg font-semibold mb-3">Subscribers</h2>
          <div class="bg-admin-bg rounded-xl p-4 h-56">
            <canvas
              id="subscriber-chart"
              phx-hook="AnalyticsChart"
              data-chart-event="chart:subscribers"
              data-test="subscriber-chart"
              aria-label="Daily subscriber count chart"
              role="img"
            >
            </canvas>
          </div>
        </section>

        <%!-- Revenue chart --%>
        <section aria-label="Revenue trend">
          <h2 class="text-lg font-semibold mb-3">Revenue</h2>
          <div class="bg-admin-bg rounded-xl p-4 h-56">
            <canvas
              id="revenue-chart"
              phx-hook="AnalyticsChart"
              data-chart-event="chart:revenue"
              data-test="revenue-chart"
              aria-label="Daily revenue chart"
              role="img"
            >
            </canvas>
          </div>
        </section>

        <%!-- Content performance table --%>
        <section aria-label="Content performance">
          <h2 class="text-lg font-semibold mb-3">Content Performance</h2>
          <div class="overflow-x-auto rounded-xl border border-admin-border">
            <table class="table w-full">
              <thead>
                <tr>
                  <.sort_th
                    col="title"
                    label="Title"
                    sort_by={@sort_by}
                    sort_dir={@sort_dir}
                  />
                  <.sort_th
                    col="unique_viewers"
                    label="Unique Viewers"
                    sort_by={@sort_by}
                    sort_dir={@sort_dir}
                  />
                  <.sort_th
                    col="avg_watch_percentage"
                    label="Avg Watch %"
                    sort_by={@sort_by}
                    sort_dir={@sort_dir}
                  />
                  <.sort_th
                    col="completion_rate"
                    label="Completion %"
                    sort_by={@sort_by}
                    sort_dir={@sort_dir}
                  />
                  <.sort_th
                    col="watchlist_adds"
                    label="Watchlist"
                    sort_by={@sort_by}
                    sort_dir={@sort_dir}
                  />
                  <.sort_th
                    col="favorites"
                    label="Favorites"
                    sort_by={@sort_by}
                    sort_dir={@sort_dir}
                  />
                  <th>
                    <span class="text-xs font-semibold uppercase tracking-wide">
                      Top Drop-off
                    </span>
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :if={@content_performance.results == []}
                  data-test="content-empty-state"
                >
                  <td colspan="7" class="text-center py-8 text-admin-muted">
                    No content data yet.
                  </td>
                </tr>
                <tr
                  :for={row <- @content_performance.results}
                  data-test={"content-row-#{row.video_id}"}
                >
                  <td class="font-medium">
                    <.link
                      navigate={~p"/admin/analytics/videos/#{row.video_id}"}
                      class="hover:underline"
                      data-test={"content-title-link-#{row.video_id}"}
                    >
                      {row.title}
                    </.link>
                  </td>
                  <td>{row.unique_viewers}</td>
                  <td>{row.avg_watch_percentage}%</td>
                  <td>{row.completion_rate}%</td>
                  <td>{row.watchlist_adds}</td>
                  <td>{row.favorites}</td>
                  <td data-test={"drop-off-cell-#{row.video_id}"}>
                    {format_top_drop_off(row.top_drop_off)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.pagination
            :if={@content_performance.total_pages > 1}
            page={@content_performance.page}
            total_pages={@content_performance.total_pages}
          />
        </section>

        <%!-- Engagement metrics --%>
        <section aria-label="Engagement metrics" class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div class="bg-admin-bg rounded-xl p-5 space-y-3">
            <h2 class="text-lg font-semibold">Engagement</h2>
            <.metric_row
              label="Continue Watching Rate"
              value={"#{@engagement.continue_watching_conversion_rate}%"}
              data_test="metric-continue-watching"
            />
            <.metric_row
              label="Queue Usage"
              value={"#{@engagement.queue_usage_percent}%"}
              data_test="metric-queue-usage"
            />
            <.metric_row
              label="Avg Queue Size"
              value={@engagement.avg_queue_size}
              data_test="metric-avg-queue-size"
            />
          </div>

          <div class="bg-admin-bg rounded-xl p-5 space-y-3">
            <h2 class="text-lg font-semibold">Top Queued</h2>
            <div :if={@engagement.most_queued_videos == []} class="text-admin-muted text-sm">
              No queue data yet.
            </div>
            <.metric_row
              :for={v <- @engagement.most_queued_videos}
              label={v.title}
              value={v.count}
              data_test={"queued-video-#{v.video_id}"}
            />
          </div>
        </section>

        <%!-- Churn indicators --%>
        <section aria-label="Churn indicators" class="bg-admin-bg rounded-xl p-5 space-y-3">
          <h2 class="text-lg font-semibold">Churn Indicators</h2>
          <div class="grid grid-cols-3 gap-4">
            <.kpi_card
              label="Dunning"
              value={@churn.dunning_count}
              data_test="churn-dunning"
            />
            <.kpi_card
              label="Cancellations"
              value={@churn.cancellations_in_period}
              data_test="churn-cancellations"
            />
            <.kpi_card
              label="Trial Conversion"
              value={"#{@churn.trial_conversion_rate}%"}
              data_test="churn-trial-conversion"
            />
          </div>
        </section>

        <%!-- Series analytics --%>
        <section :if={@series_list != []} aria-label="Series analytics">
          <h2 class="text-lg font-semibold mb-3">Series</h2>
          <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <.link
              :for={series <- @series_list}
              navigate={~p"/admin/analytics/series/#{series.id}"}
              class="bg-admin-bg rounded-xl p-5 hover:bg-admin-card transition-colors"
              data-test={"series-analytics-link-#{series.id}"}
            >
              <p class="font-semibold">{series.title}</p>
              <p class="text-sm text-admin-muted mt-1">
                View retention &amp; completion stats
              </p>
            </.link>
          </div>
        </section>
      </div>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :data_test, :string, required: true

  defp kpi_card(assigns) do
    ~H"""
    <div class="bg-admin-bg rounded-xl p-5" data-test={@data_test}>
      <p class="text-sm text-admin-muted">{@label}</p>
      <p class="text-2xl font-bold mt-1">{@value}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :data_test, :string, required: true

  defp metric_row(assigns) do
    ~H"""
    <div class="flex justify-between items-center" data-test={@data_test}>
      <span class="text-sm text-admin-muted">{@label}</span>
      <span class="font-semibold">{@value}</span>
    </div>
    """
  end

  attr :col, :string, required: true
  attr :label, :string, required: true
  attr :sort_by, :atom, required: true
  attr :sort_dir, :atom, required: true

  defp sort_th(assigns) do
    ~H"""
    <th>
      <button
        phx-click="sort_content"
        phx-value-col={@col}
        data-test={"sort-col-#{@col}"}
        class="flex items-center gap-1 text-xs font-semibold uppercase tracking-wide hover:text-admin-accent transition-colors"
        aria-sort={aria_sort(@sort_by, @col, @sort_dir)}
      >
        {@label}
        <span :if={@sort_by == String.to_existing_atom(@col)} aria-hidden="true">
          {if @sort_dir == :asc, do: "↑", else: "↓"}
        </span>
      </button>
    </th>
    """
  end

  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true

  defp pagination(assigns) do
    ~H"""
    <div class="flex items-center justify-center gap-2 mt-4" data-test="content-pagination">
      <button
        :if={@page > 1}
        phx-click="content_page"
        phx-value-page={@page - 1}
        data-test="content-page-prev"
        class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
        aria-label="Previous page"
      >
        &lsaquo;
      </button>
      <span class="text-sm text-admin-muted">Page {@page} of {@total_pages}</span>
      <button
        :if={@page < @total_pages}
        phx-click="content_page"
        phx-value-page={@page + 1}
        data-test="content-page-next"
        class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
        aria-label="Next page"
      >
        &rsaquo;
      </button>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_all_data(socket, org, period) do
    overview = Analytics.get_overview_cards(org, period)
    engagement = Analytics.get_engagement_metrics(org, period)
    churn = Analytics.get_churn_indicators(org, period)

    content =
      Analytics.list_content_performance(org, period,
        sort_by: socket.assigns.sort_by,
        sort_dir: socket.assigns.sort_dir,
        page: socket.assigns.content_page,
        per_page: 20
      )

    today = Date.utc_today()
    from_date = period_start_date(period)

    subscriber_data = Analytics.list_daily_subscriber_counts(org, from_date, today)
    revenue_data = Analytics.list_daily_revenue(org, from_date, today)

    sub_labels = Enum.map(subscriber_data, &Date.to_string(&1.period_date))
    sub_values = Enum.map(subscriber_data, &Decimal.to_integer(&1.value))

    rev_labels = Enum.map(revenue_data, &Date.to_string(&1.period_date))
    rev_values = Enum.map(revenue_data, &Decimal.to_integer(&1.value))

    series_list = Content.list_series(org, per_page: 100).results

    socket
    |> assign(overview: overview)
    |> assign(engagement: engagement)
    |> assign(churn: churn)
    |> assign(content_performance: content)
    |> assign(series_list: series_list)
    |> push_event("chart:subscribers", %{labels: sub_labels, data: sub_values, type: "line"})
    |> push_event("chart:revenue", %{labels: rev_labels, data: rev_values, type: "bar"})
  end

  defp format_cents(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    cents_rem = abs(rem(cents, 100))
    "#{dollars}.#{String.pad_leading(to_string(cents_rem), 2, "0")}"
  end

  defp format_cents(_), do: "0.00"

  defp format_seconds(secs) when is_float(secs) or is_integer(secs) do
    total = trunc(secs)
    minutes = div(total, 60)
    remaining = rem(total, 60)
    "#{minutes}m #{remaining}s"
  end

  defp format_seconds(_), do: "0m 0s"

  defp format_top_drop_off(nil), do: "—"

  defp format_top_drop_off(%{start_seconds: s, end_seconds: e, count: n}) do
    "#{s}–#{e}s (#{n})"
  end

  defp period_btn_class(current, value) when current == value do
    "inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-3 py-1.5 font-ui text-sm font-medium text-admin-on-accent hover:brightness-110"
  end

  defp period_btn_class(_current, _value) do
    "inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
  end

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(_), do: :asc

  defp aria_sort(sort_by, col, sort_dir) do
    if sort_by == String.to_existing_atom(col) do
      if sort_dir == :asc, do: "ascending", else: "descending"
    else
      "none"
    end
  end

  defp period_start_date("7"), do: Date.add(Date.utc_today(), -7)
  defp period_start_date("30"), do: Date.add(Date.utc_today(), -30)
  defp period_start_date("90"), do: Date.add(Date.utc_today(), -90)
  defp period_start_date(_), do: Date.add(Date.utc_today(), -30)
end
