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

  it("clears the pending auto-start when destroyed repeatedly before the deadline", () => {
    const tour = fakeTour()
    mockedBuild.mockReturnValue(tour as never)
    const { hook, pushEvent } = mountHook(GuidedTour, html(`<div id="tour" data-auto-start="true"></div>`))

    vi.advanceTimersByTime(200)
    hook.destroyed()
    hook.destroyed()
    expect(vi.getTimerCount()).toBe(0)
    vi.advanceTimersByTime(1000)

    expect(mockedBuild).not.toHaveBeenCalled()
    expect(tour.start).not.toHaveBeenCalled()
    expect(pushEvent).not.toHaveBeenCalled()
  })

  it.each(["complete", "cancel"])("consumes auto-start when manually started and %s before its deadline", (event) => {
    const tour = fakeTour()
    mockedBuild.mockReturnValue(tour as never)
    const { serverPush, pushEvent } = mountHook(GuidedTour, html(`<div id="tour" data-auto-start="true"></div>`))

    vi.advanceTimersByTime(100)
    serverPush("start-tour")
    expect(vi.getTimerCount()).toBe(0)
    vi.advanceTimersByTime(100)
    tour.emit(event)
    vi.advanceTimersByTime(1000)

    expect(mockedBuild).toHaveBeenCalledTimes(1)
    expect(tour.start).toHaveBeenCalledTimes(1)
    expect(pushEvent).toHaveBeenCalledExactlyOnceWith("tour_completed", {})
  })

  it.each(["auto", "manual"])("repeated destruction cancels an %s-started tour once with current completion semantics", (start) => {
    const tour = fakeTour()
    tour.cancel.mockImplementation(() => tour.emit("cancel"))
    mockedBuild.mockReturnValue(tour as never)
    const { hook, serverPush, pushEvent } = mountHook(GuidedTour, html(`<div id="tour" data-auto-start="true"></div>`))

    if (start === "auto") vi.advanceTimersByTime(400)
    else serverPush("start-tour")
    hook.destroyed()
    hook.destroyed()
    vi.advanceTimersByTime(1000)

    expect(mockedBuild).toHaveBeenCalledTimes(1)
    expect(tour.cancel).toHaveBeenCalledTimes(1)
    expect(pushEvent).toHaveBeenCalledExactlyOnceWith("tour_completed", {})
    expect(vi.getTimerCount()).toBe(0)
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
