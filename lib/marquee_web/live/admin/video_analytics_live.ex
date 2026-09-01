defmodule MarqueeWeb.Admin.VideoAnalyticsLive do
  @moduledoc """
  Per-video analytics page showing the drop-off distribution.

  Route: /admin/analytics/videos/:video_id
  """

  use MarqueeWeb, :live_view

  alias Marquee.Analytics
  alias Marquee.Content

  @impl true
  def mount(%{"video_id" => video_id}, _session, socket) do
    org = socket.assigns.organization

    case Content.get_video(org, video_id) do
      {:ok, video} ->
        distribution = Analytics.drop_off_distribution(org, video.id)
        watch_stats = Analytics.get_video_watch_stats(org, video.id)

        socket =
          socket
          |> assign(page_title: "Analytics: #{video.title}")
          |> assign(video: video)
          |> assign(distribution: distribution)
          |> assign(watch_stats: watch_stats)
          |> push_distribution_event(distribution)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Video not found")
         |> push_navigate(to: ~p"/admin/analytics")}
    end
  end

  defp push_distribution_event(socket, %{buckets: buckets}) do
    labels = Enum.map(buckets, &"#{&1.start_seconds}–#{&1.end_seconds}s")
    data = Enum.map(buckets, & &1.percentage)

    push_event(socket, "chart:drop_off", %{labels: labels, data: data, type: "bar"})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <div class="space-y-8">
        <div class="flex flex-col gap-2">
          <.link navigate={~p"/admin/analytics"} class="text-sm text-admin-muted hover:underline">
            &larr; Back to analytics
          </.link>
          <.header>{@video.title}</.header>
        </div>

        <section aria-label="Watch stats" class="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <div class="bg-admin-bg rounded-xl p-5" data-test="kpi-unique-viewers">
            <p class="text-sm text-admin-muted">Unique Viewers</p>
            <p class="text-2xl font-bold mt-1">{@watch_stats.unique_viewers}</p>
          </div>

          <div class="bg-admin-bg rounded-xl p-5" data-test="kpi-avg-watch-pct">
            <p class="text-sm text-admin-muted">Avg Watch %</p>
            <p class="text-2xl font-bold mt-1">{@watch_stats.avg_watch_percentage}%</p>
          </div>

          <div class="bg-admin-bg rounded-xl p-5" data-test="kpi-total-drop-offs">
            <p class="text-sm text-admin-muted">Total drop-offs</p>
            <p class="text-2xl font-bold mt-1">{@distribution.total}</p>
          </div>

          <div class="bg-admin-bg rounded-xl p-5" data-test="kpi-drop-off-time">
            <p class="text-sm text-admin-muted">Peak drop-off time</p>
            <p class="text-2xl font-bold mt-1">{worst_bucket_time(@distribution)}</p>
          </div>
        </section>

        <section aria-label="Drop-off distribution">
          <h2 class="text-lg font-semibold mb-3">Drop-off distribution</h2>
          <div class="bg-admin-bg rounded-xl p-4 h-72">
            <canvas
              :if={@distribution.buckets != []}
              id="drop-off-chart"
              phx-hook="AnalyticsChart"
              data-chart-event="chart:drop_off"
              data-test="drop-off-chart"
              aria-label="Drop-off distribution by 10-second bucket"
              role="img"
            >
            </canvas>
            <p
              :if={@distribution.buckets == []}
              data-test="drop-off-empty-state"
              class="text-admin-muted text-sm text-center py-12"
            >
              No drop-off data yet for this video.
            </p>
          </div>
        </section>
      </div>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp worst_bucket_time(%{buckets: []}), do: "—"

  defp worst_bucket_time(%{buckets: buckets}) do
    worst = Enum.max_by(buckets, & &1.count)
    "#{format_timestamp(worst.start_seconds)}–#{format_timestamp(worst.end_seconds)}"
  end

  defp format_timestamp(seconds) when seconds < 60, do: "0:#{pad(seconds)}"

  defp format_timestamp(seconds) do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    "#{m}:#{pad(s)}"
  end

  defp pad(n), do: String.pad_leading(to_string(n), 2, "0")
end
