defmodule BobineWeb.Admin.SeriesAnalyticsLive do
  @moduledoc """
  Series-level analytics page.

  Shows per-season completion stats and lets the operator drill into a
  season. Period selector matches the org analytics dashboard.

  Route: /admin/analytics/series/:series_id
  """

  use BobineWeb, :live_view

  alias Bobine.Analytics
  alias Bobine.Content

  @default_period "30"

  @impl true
  def mount(%{"series_id" => series_id}, _session, socket) do
    org = socket.assigns.organization

    case Content.get_series(org, series_id) do
      {:ok, series} ->
        period = @default_period
        season_stats = Analytics.list_season_stats(org, series, period)

        socket =
          socket
          |> assign(page_title: "Analytics: #{series.title}")
          |> assign(series: series)
          |> assign(period: period)
          |> assign(season_stats: season_stats)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Series not found")
         |> push_navigate(to: ~p"/admin/analytics")}
    end
  end

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) do
    org = socket.assigns.organization
    season_stats = Analytics.list_season_stats(org, socket.assigns.series, period)

    {:noreply,
     socket
     |> assign(period: period)
     |> assign(season_stats: season_stats)}
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
        <div class="flex flex-col gap-2">
          <.link navigate={~p"/admin/analytics"} class="text-sm text-base-content/60 hover:underline">
            &larr; Back to analytics
          </.link>
          <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <.header>{@series.title}</.header>

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
        </div>

        <section aria-label="Season overview" class="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <div class="bg-base-200 rounded-xl p-5" data-test="kpi-total-seasons">
            <p class="text-sm text-base-content/60">Seasons</p>
            <p class="text-2xl font-bold mt-1">{length(@season_stats)}</p>
          </div>
          <div class="bg-base-200 rounded-xl p-5" data-test="kpi-total-starters">
            <p class="text-sm text-base-content/60">Starters</p>
            <p class="text-2xl font-bold mt-1">{total_starters(@season_stats)}</p>
          </div>
          <div class="bg-base-200 rounded-xl p-5" data-test="kpi-total-finishers">
            <p class="text-sm text-base-content/60">Finishers</p>
            <p class="text-2xl font-bold mt-1">{total_finishers(@season_stats)}</p>
          </div>
          <div class="bg-base-200 rounded-xl p-5" data-test="kpi-overall-completion">
            <p class="text-sm text-base-content/60">Overall completion</p>
            <p class="text-2xl font-bold mt-1">{overall_rate(@season_stats)}%</p>
          </div>
        </section>

        <section aria-label="Per-season stats">
          <h2 class="text-lg font-semibold mb-3">Seasons</h2>

          <div class="overflow-x-auto rounded-xl border border-base-300">
            <table class="table w-full">
              <thead>
                <tr>
                  <th class="text-xs font-semibold uppercase tracking-wide">#</th>
                  <th class="text-xs font-semibold uppercase tracking-wide">Title</th>
                  <th class="text-xs font-semibold uppercase tracking-wide">Episodes</th>
                  <th class="text-xs font-semibold uppercase tracking-wide">Starters</th>
                  <th class="text-xs font-semibold uppercase tracking-wide">Finishers</th>
                  <th class="text-xs font-semibold uppercase tracking-wide">Completion</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@season_stats == []} data-test="season-empty-state">
                  <td colspan="7" class="text-center py-8 text-base-content/50">
                    No seasons yet.
                  </td>
                </tr>
                <tr
                  :for={row <- @season_stats}
                  data-test={"season-row-#{row.season_id}"}
                >
                  <td>{row.season_number}</td>
                  <td class="font-medium">{row.title}</td>
                  <td>{row.episode_count}</td>
                  <td>{row.starters}</td>
                  <td>{row.finishers}</td>
                  <td>{row.completion_rate}%</td>
                  <td>
                    <.link
                      navigate={~p"/admin/analytics/series/#{@series.id}/seasons/#{row.season_id}"}
                      class="text-sm text-primary hover:underline"
                      data-test={"season-drill-#{row.season_id}"}
                    >
                      View
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp total_starters(season_stats), do: Enum.sum(Enum.map(season_stats, & &1.starters))

  defp total_finishers(season_stats), do: Enum.sum(Enum.map(season_stats, & &1.finishers))

  defp overall_rate(season_stats) do
    starters = total_starters(season_stats)

    if starters > 0 do
      Float.round(total_finishers(season_stats) / starters * 100, 1)
    else
      0.0
    end
  end

  defp period_btn_class(current, value) when current == value do
    "btn btn-sm btn-primary"
  end

  defp period_btn_class(_current, _value) do
    "btn btn-sm btn-ghost"
  end
end
