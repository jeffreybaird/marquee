defmodule BobineWeb.Admin.SeasonAnalyticsLive do
  @moduledoc """
  Season-level analytics page: episode funnel, drop-off episode, and
  next-season start rate.

  Route: /admin/analytics/series/:series_id/seasons/:season_id
  """

  use BobineWeb, :live_view

  alias Bobine.Analytics
  alias Bobine.Content

  @default_period "30"

  @impl true
  def mount(%{"series_id" => series_id, "season_id" => season_id}, _session, socket) do
    org = socket.assigns.organization

    with {:ok, series} <- Content.get_series(org, series_id),
         {:ok, season} <- Content.get_season(org, season_id),
         true <- season.series_id == series.id do
      period = @default_period

      socket =
        socket
        |> assign(page_title: "Analytics: #{season.title}")
        |> assign(series: series)
        |> assign(season: season)
        |> assign(period: period)
        |> load_all_data(org, season, period)

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Season not found")
         |> push_navigate(to: ~p"/admin/analytics")}
    end
  end

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) do
    org = socket.assigns.organization
    season = socket.assigns.season

    socket =
      socket
      |> assign(period: period)
      |> load_all_data(org, season, period)

    {:noreply, socket}
  end

  defp load_all_data(socket, org, season, period) do
    funnel = Analytics.episode_funnel(org, season, period)
    completion = Analytics.season_completion_rate(org, season, period)
    drop_off = Analytics.drop_off_episode(org, season, period)
    next_season = Analytics.next_season_start_rate(org, season, period)

    socket
    |> assign(funnel: funnel)
    |> assign(completion: completion)
    |> assign(drop_off_episode: drop_off)
    |> assign(next_season: next_season)
    |> push_funnel_event(funnel)
  end

  defp push_funnel_event(socket, funnel) do
    labels = Enum.map(funnel, &"E#{&1.episode_number}")
    data = Enum.map(funnel, & &1.completions)
    push_event(socket, "chart:episode_funnel", %{labels: labels, data: data, type: "bar"})
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
          <.link
            navigate={~p"/admin/analytics/series/#{@series.id}"}
            class="text-sm text-base-content/60 hover:underline"
          >
            &larr; Back to {@series.title}
          </.link>

          <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <.header>
              Season {@season.season_number}: {@season.title}
            </.header>

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
          <div class="bg-base-200 rounded-xl p-5" data-test="kpi-starters">
            <p class="text-sm text-base-content/60">Starters</p>
            <p class="text-2xl font-bold mt-1">{@completion.starters}</p>
          </div>
          <div class="bg-base-200 rounded-xl p-5" data-test="kpi-finishers">
            <p class="text-sm text-base-content/60">Finishers</p>
            <p class="text-2xl font-bold mt-1">{@completion.finishers}</p>
          </div>
          <div class="bg-base-200 rounded-xl p-5" data-test="kpi-completion-rate">
            <p class="text-sm text-base-content/60">Completion rate</p>
            <p class="text-2xl font-bold mt-1">{@completion.completion_rate}%</p>
          </div>
          <div class="bg-base-200 rounded-xl p-5" data-test="kpi-drop-off-episode">
            <p class="text-sm text-base-content/60">Drop-off episode</p>
            <p class="text-2xl font-bold mt-1">{drop_off_label(@drop_off_episode)}</p>
          </div>
        </section>

        <section aria-label="Episode funnel">
          <h2 class="text-lg font-semibold mb-3">Episode funnel</h2>
          <div class="bg-base-200 rounded-xl p-4 h-72">
            <canvas
              :if={@funnel != []}
              id="episode-funnel-chart"
              phx-hook="AnalyticsChart"
              data-chart-event="chart:episode_funnel"
              data-test="episode-funnel-chart"
              aria-label="Episode completions by episode number"
              role="img"
            >
            </canvas>
            <p
              :if={@funnel == []}
              data-test="funnel-empty-state"
              class="text-base-content/50 text-sm text-center py-12"
            >
              This season has no episodes yet.
            </p>
          </div>
        </section>

        <section aria-label="Next season">
          <h2 class="text-lg font-semibold mb-3">Continuation to next season</h2>
          <div class="bg-base-200 rounded-xl p-5">
            <div :if={@next_season.next_season_id} class="space-y-2">
              <p class="text-sm text-base-content/60">
                {@next_season.next_season_starters} of {@next_season.eligible} viewers who completed this season reached 25% of the next season's first episode.
              </p>
              <p class="text-3xl font-bold" data-test="next-season-rate">
                {@next_season.rate}%
              </p>
            </div>
            <p
              :if={is_nil(@next_season.next_season_id)}
              data-test="next-season-none"
              class="text-base-content/60 text-sm"
            >
              No next season in this series yet.
            </p>
          </div>
        </section>
      </div>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp drop_off_label(nil), do: "—"

  defp drop_off_label(%{episode_number: num, drop_off_count: count}) do
    "E#{num} (#{count})"
  end

  defp period_btn_class(current, value) when current == value do
    "btn btn-sm btn-primary"
  end

  defp period_btn_class(_current, _value) do
    "btn btn-sm btn-ghost"
  end
end
