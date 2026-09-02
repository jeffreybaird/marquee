import { afterEach, describe, expect, it, vi } from "vitest"

import AnalyticsChart from "../../js/hooks/analytics_chart_hook"
import Chart from "../../vendor/chart.js"
import { html, mountHook } from "../support/mount"

// jsdom has no canvas context, so Chart.js cannot render. Replace the vendored
// bundle with a double that records its configuration.
vi.mock("../../vendor/chart.js", () => {
  class FakeChart {
    static created: FakeChart[] = []
    data: { labels?: unknown[]; datasets: { data: unknown[] }[] }
    update = vi.fn()
    destroy = vi.fn()

    constructor(
      public canvas: HTMLCanvasElement,
      public config: { type: string; data: FakeChart["data"]; options: Record<string, unknown> },
    ) {
      this.data = config.data
      FakeChart.created.push(this)
    }
  }
  return { default: FakeChart }
})

type FakeChartClass = { created: (Chart & { canvas: HTMLCanvasElement; config: Record<string, unknown> })[] }
const FakeChart = Chart as unknown as FakeChartClass

const canvas = (event?: string) =>
  html<HTMLCanvasElement>(
    `<canvas id="chart" ${event === undefined ? "" : `data-chart-event="${event}"`}></canvas>`,
  )

describe("AnalyticsChart", () => {
  afterEach(() => {
    FakeChart.created = []
    document.body.innerHTML = ""
  })

  it("listens for the event named in data-chart-event", () => {
    const { handledEvents } = mountHook(AnalyticsChart, canvas("chart:subscribers"))

    expect(handledEvents()).toEqual(["chart:subscribers"])
  })

  it("registers nothing without an event name", () => {
    const { handledEvents } = mountHook(AnalyticsChart, canvas())

    expect(handledEvents()).toEqual([])
  })

  it("renders a filled line chart by default on the first payload", () => {
    const el = canvas("chart:views")
    const { serverPush } = mountHook(AnalyticsChart, el)

    serverPush("chart:views", { labels: ["Mon", "Tue"], data: [1, 2] })

    expect(FakeChart.created).toHaveLength(1)
    const { canvas: target, config } = FakeChart.created[0]
    expect(target).toBe(el)
    expect(config.type).toBe("line")
    expect(config.data).toEqual({
      labels: ["Mon", "Tue"],
      datasets: [expect.objectContaining({ data: [1, 2], fill: true })],
    })
    expect(config.options).toMatchObject({
      responsive: true,
      scales: { y: { beginAtZero: true } },
    })
  })

  it("updates the existing chart in place on later payloads", () => {
    const { serverPush } = mountHook(AnalyticsChart, canvas("chart:views"))
    serverPush("chart:views", { labels: ["Mon"], data: [1] })

    serverPush("chart:views", { labels: ["Mon", "Tue"], data: [1, 5] })

    expect(FakeChart.created).toHaveLength(1)
    const chart = FakeChart.created[0]
    expect(chart.data.labels).toEqual(["Mon", "Tue"])
    expect(chart.data.datasets[0].data).toEqual([1, 5])
    expect(chart.update).toHaveBeenCalledWith("none")
  })

  it("renders doughnut charts unfilled and without axes", () => {
    const { serverPush } = mountHook(AnalyticsChart, canvas("chart:plans"))

    serverPush("chart:plans", { labels: ["Free", "Pro"], data: [3, 4], type: "doughnut" })

    const { config } = FakeChart.created[0]
    expect(config.type).toBe("doughnut")
    expect(config.data).toMatchObject({ datasets: [{ fill: false }] })
    expect(config.options).toMatchObject({ scales: {} })
  })

  it("destroys the chart when the hook is destroyed", () => {
    const { hook, serverPush } = mountHook(AnalyticsChart, canvas("chart:views"))
    serverPush("chart:views", { labels: [], data: [] })

    hook.destroyed()

    expect(FakeChart.created[0].destroy).toHaveBeenCalledTimes(1)
    expect(() => hook.destroyed()).not.toThrow()
  })
})
