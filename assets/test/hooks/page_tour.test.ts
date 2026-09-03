import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import PageTour from "../../js/hooks/page_tour"
import { buildTour } from "../../js/tour"
import { CONTENT_TOUR_STEPS } from "../../js/tour/steps"
import { html, mountHook } from "../support/mount"

vi.mock("../../js/tour", () => ({ buildTour: vi.fn() }))

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

const mockedBuild = vi.mocked(buildTour)

const pageEl = (attrs: string) =>
  html(`<div id="page-tour" data-tour-page="content" ${attrs}></div>`)

describe("PageTour", () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
    mockedBuild.mockReset()
    document.body.innerHTML = ""
  })

  it("auto-starts 400ms after mount with the page's steps and org brand", () => {
    const tour = fakeTour()
    mockedBuild.mockReturnValue(tour as never)
    mountHook(PageTour, pageEl(`data-auto-start="true" data-tour-brand="Acme"`))

    vi.advanceTimersByTime(399)
    expect(tour.start).not.toHaveBeenCalled()

    vi.advanceTimersByTime(1)
    expect(mockedBuild).toHaveBeenCalledWith(CONTENT_TOUR_STEPS, "Acme")
    expect(tour.start).toHaveBeenCalledTimes(1)
  })

  it("does not auto-start unless asked, and defaults the brand", () => {
    const tour = fakeTour()
    mockedBuild.mockReturnValue(tour as never)
    const { serverPush } = mountHook(PageTour, pageEl(`data-auto-start="false"`))

    vi.advanceTimersByTime(1000)
    expect(tour.start).not.toHaveBeenCalled()

    serverPush("start-page-tour")
    expect(mockedBuild).toHaveBeenCalledWith(CONTENT_TOUR_STEPS, "Marquee")
    expect(tour.start).toHaveBeenCalledTimes(1)
  })

  it("reports completion to the server once, with the page key", () => {
    const tour = fakeTour()
    mockedBuild.mockReturnValue(tour as never)
    const { pushEvent, serverPush } = mountHook(PageTour, pageEl(""))

    serverPush("start-page-tour")
    tour.emit("complete")

    expect(pushEvent).toHaveBeenCalledWith("page_tour_completed", { page: "content" })
    expect(pushEvent).toHaveBeenCalledTimes(1)
  })

  it("reports dismissal the same way", () => {
    const tour = fakeTour()
    mockedBuild.mockReturnValue(tour as never)
    const { pushEvent, serverPush } = mountHook(PageTour, pageEl(""))

    serverPush("start-page-tour")
    tour.emit("cancel")

    expect(pushEvent).toHaveBeenCalledWith("page_tour_completed", { page: "content" })
  })

  it("is inert for a page with no registered tour", () => {
    const tour = fakeTour()
    mockedBuild.mockReturnValue(tour as never)
    const el = html(`<div id="page-tour" data-tour-page="nope" data-auto-start="true"></div>`)
    const { pushEvent } = mountHook(PageTour, el)

    vi.advanceTimersByTime(1000)
    expect(mockedBuild).not.toHaveBeenCalled()
    expect(pushEvent).not.toHaveBeenCalled()
  })

  it("refuses to start a second tour while one is open", () => {
    const first = fakeTour()
    const second = fakeTour()
    mockedBuild.mockReturnValueOnce(first as never).mockReturnValueOnce(second as never)
    const { serverPush } = mountHook(PageTour, pageEl(""))

    serverPush("start-page-tour")
    serverPush("start-page-tour")
    expect(mockedBuild).toHaveBeenCalledTimes(1)

    first.emit("cancel")
    serverPush("start-page-tour")
    expect(second.start).toHaveBeenCalledTimes(1)
  })

  it("cancels an open tour when destroyed, and is a no-op otherwise", () => {
    const tour = fakeTour()
    mockedBuild.mockReturnValue(tour as never)
    const { hook, serverPush } = mountHook(PageTour, pageEl(""))

    hook.destroyed()
    expect(tour.cancel).not.toHaveBeenCalled()

    serverPush("start-page-tour")
    hook.destroyed()
    expect(tour.cancel).toHaveBeenCalledTimes(1)
  })
})
