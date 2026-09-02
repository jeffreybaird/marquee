import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import GuidedTour from "../../js/hooks/guided_tour"
import { buildAdminTour } from "../../js/tour"
import { html, mountHook } from "../support/mount"

vi.mock("../../js/tour", () => ({ buildAdminTour: vi.fn() }))

/** A tour double with the surface the hook uses. */
function fakeTour() {
  const handlers = new Map<string, () => void>()
  return {
    on: vi.fn((event: string, handler: () => void) => {
      handlers.set(event, handler)
    }),
    start: vi.fn(),
    cancel: vi.fn(),
    emit: (event: string) => handlers.get(event)?.(),
  }
}

const mockedBuild = vi.mocked(buildAdminTour)

describe("GuidedTour", () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  it("auto-starts 400ms after mount with the org brand", () => {
    const tour = fakeTour()
    mockedBuild.mockReturnValue(tour as never)
    mountHook(GuidedTour, html(`<div id="tour" data-auto-start="true" data-tour-brand="Acme"></div>`))

    vi.advanceTimersByTime(399)
    expect(tour.start).not.toHaveBeenCalled()

    vi.advanceTimersByTime(1)
    expect(mockedBuild).toHaveBeenCalledWith("Acme")
    expect(tour.start).toHaveBeenCalledTimes(1)
  })

  it("does not auto-start unless asked, and defaults the brand", () => {
    const tour = fakeTour()
    mockedBuild.mockReturnValue(tour as never)
    const { serverPush } = mountHook(GuidedTour, html(`<div id="tour" data-auto-start="false"></div>`))

    vi.advanceTimersByTime(1000)
    expect(tour.start).not.toHaveBeenCalled()

    serverPush("start-tour")
    expect(mockedBuild).toHaveBeenCalledWith("Marquee")
    expect(tour.start).toHaveBeenCalledTimes(1)
  })

  it("reports completion or dismissal to the server once", () => {
    const tour = fakeTour()
    mockedBuild.mockReturnValue(tour as never)
    const { pushEvent, serverPush } = mountHook(GuidedTour, html(`<div id="tour"></div>`))

    serverPush("start-tour")
    tour.emit("complete")

    expect(pushEvent).toHaveBeenCalledWith("tour_completed", {})
    expect(pushEvent).toHaveBeenCalledTimes(1)
  })

  it("refuses to start a second tour while one is open, then allows a new one after it ends", () => {
    const first = fakeTour()
    const second = fakeTour()
    mockedBuild.mockReturnValueOnce(first as never).mockReturnValueOnce(second as never)
    const { serverPush } = mountHook(GuidedTour, html(`<div id="tour"></div>`))

    serverPush("start-tour")
    serverPush("start-tour")
    expect(mockedBuild).toHaveBeenCalledTimes(1)

    first.emit("cancel")
    serverPush("start-tour")
    expect(second.start).toHaveBeenCalledTimes(1)
  })

  it("cancels an open tour when destroyed, and is a no-op otherwise", () => {
    const tour = fakeTour()
    mockedBuild.mockReturnValue(tour as never)
    const { hook, serverPush } = mountHook(GuidedTour, html(`<div id="tour"></div>`))

    hook.destroyed()
    expect(tour.cancel).not.toHaveBeenCalled()

    serverPush("start-tour")
    hook.destroyed()
    expect(tour.cancel).toHaveBeenCalledTimes(1)
  })
})
