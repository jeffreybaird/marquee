/**
 * AnalyticsChart hook — shared between operator and super-admin dashboards.
 *
 * Usage:
 *   <canvas id="my-chart" phx-hook="AnalyticsChart" data-chart-event="chart:subscribers" />
 *
 * The server sends push_event(socket, data-chart-event, %{labels: [...], data: [...], type: "line"})
 * This hook renders or updates a Chart.js chart on each received event.
 *
 * Supported types: "line", "bar", "doughnut"
 * Cleans up the Chart.js instance on unmount.
 */
import { ViewHook } from "phoenix_live_view"
import Chart from "../../vendor/chart.js"

type AnalyticsChartType = "line" | "bar" | "doughnut"

interface ChartPayload {
  labels: string[]
  data: number[]
  type?: AnalyticsChartType
}

class AnalyticsChart extends ViewHook<HTMLCanvasElement> {
  private chart: Chart<AnalyticsChartType, number[], string> | null = null
  private eventName = ""
  private handler: ((payload: ChartPayload) => void) | null = null

  mounted() {
    this.eventName = this.el.dataset.chartEvent || ""

    if (!this.eventName) return

    this.handler = (payload: ChartPayload) => {
      this.renderChart(payload)
    }

    this.handleEvent(this.eventName, this.handler)
  }

  private renderChart(payload: ChartPayload) {
    const { labels, data, type = "line" } = payload

    if (this.chart) {
      this.chart.data.labels = labels
      this.chart.data.datasets[0].data = data
      this.chart.update("none")
      return
    }

    this.chart = new Chart(this.el, {
      type,
      data: {
        labels,
        datasets: [
          {
            data,
            borderColor: "rgb(59, 130, 246)",
            backgroundColor:
              type === "line"
                ? "rgba(59, 130, 246, 0.1)"
                : "rgba(59, 130, 246, 0.7)",
            fill: type === "line",
            tension: 0.4,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
        },
        scales:
          type !== "doughnut"
            ? {
                x: {
                  grid: { color: "rgba(255,255,255,0.05)" },
                  ticks: { color: "rgba(255,255,255,0.6)", maxTicksLimit: 8 },
                },
                y: {
                  grid: { color: "rgba(255,255,255,0.05)" },
                  ticks: { color: "rgba(255,255,255,0.6)" },
                  beginAtZero: true,
                },
              }
            : {},
      },
    })
  }

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
    this.handler = null
    this.eventName = ""
  }
}

export default AnalyticsChart
