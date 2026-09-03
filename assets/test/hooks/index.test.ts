import { describe, expect, it, vi } from "vitest"
import { ViewHook } from "phoenix_live_view"

import { hooks } from "../../js/hooks"

// Chart.js cannot render without a canvas context; keep the vendored bundle
// out of the registry test.
vi.mock("../../vendor/chart.js", () => ({ default: class Chart {} }))

/**
 * The registry is what `LiveSocket` receives. Every entry must be a class
 * LiveView can instantiate (`hookDefinition.prototype instanceof ViewHook`),
 * and every `phx-hook` name used in templates must resolve to one.
 */
describe("hooks registry", () => {
  const expectedNames = [
    "AnalyticsChart",
    "CardFocus",
    "Carousel",
    "ChatAutoScroll",
    "CopyToClipboard",
    "GuidedTour",
    "HeroCarousel",
    "MuxPlayer",
    "MuxUploader",
    "PageTour",
    "QueueSortable",
    "RowScroller",
    "ScrollToCurrentEpisode",
    "SpacesUploader",
    "StaggerReveal",
    "ViewerNav",
  ]

  it("registers every hook under its phx-hook name", () => {
    expect(Object.keys(hooks).sort()).toEqual(expectedNames)
  })

  it.each(expectedNames)("%s is a ViewHook class that mounts in jsdom", (name) => {
    const Hook = hooks[name as keyof typeof hooks]
    const el = document.createElement("div")
    el.id = `hook-${name}`
    document.body.appendChild(el)

    expect(Hook.prototype).toBeInstanceOf(ViewHook)
    const instance = new Hook(null, el as never)
    expect(instance.el).toBe(el)
  })
})
