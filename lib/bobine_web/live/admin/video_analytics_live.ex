defmodule BobineWeb.Admin.VideoAnalyticsLive do
  @moduledoc """
  Per-video analytics page showing the drop-off distribution.

  Route: /admin/analytics/videos/:video_id
  """

  use BobineWeb, :live_view

  alias Bobine.Analytics
  alias Bobine.Content

  @impl true
  def mount(%{"video_id" => video_id}, _session, socket) do
    org = socket.assigns.organization

    case Content.get_video(org, video_id) do
      {:ok, video} ->
        distribution = Analytics.drop_off_distribution(org, video.id)

        socket =
          socket
          |> assign(page_title: "Analytics: #{video.title}")
          |> assign(video: video)
          |> assign(distribution: distribution)
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
    <BobineWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <div class="space-y-8">
        <div class="flex flex-col gap-2">
          <.link navigate={~p"/admin/analytics"} class="text-sm text-admin-text-muted hover:underline">
            &larr; Back to analytics
          </.link>
          <.header>{@video.title}</.header>
        </div>

        <section aria-label="Drop-off overview" class="grid grid-cols-2 gap-4 lg:grid-cols-3">
          <div class="bg-admin-bg rounded-xl p-5" data-test="kpi-total-drop-offs">
            <p class="text-sm text-admin-text-muted">Total drop-offs</p>
            <p class="text-2xl font-bold mt-1">{@distribution.total}</p>
          </div>

          <div class="bg-admin-bg rounded-xl p-5" data-test="kpi-worst-bucket">
            <p class="text-sm text-admin-text-muted">Worst bucket</p>
            <p class="text-2xl font-bold mt-1">{worst_bucket_label(@distribution)}</p>
          </div>

          <div class="bg-admin-bg rounded-xl p-5" data-test="kpi-buckets-with-drops">
            <p class="text-sm text-admin-text-muted">Buckets with drops</p>
            <p class="text-2xl font-bold mt-1">{length(@distribution.buckets)}</p>
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
              class="text-admin-text-muted text-sm text-center py-12"
            >
              No drop-off data yet for this video.
            </p>
          </div>
        </section>
      </div>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp worst_bucket_label(%{buckets: []}), do: "—"

  defp worst_bucket_label(%{buckets: buckets}) do
    worst = Enum.max_by(buckets, & &1.count)
    "#{worst.start_seconds}–#{worst.end_seconds}s"
  end
end
