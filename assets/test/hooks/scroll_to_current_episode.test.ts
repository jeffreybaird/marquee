import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import ScrollToCurrentEpisode from "../../js/hooks/scroll_to_current_episode"
import { html, mountHook } from "../support/mount"

/**
 * Contract for jeffreybaird/marquee#19: the episode list (`this.el`) is its
 * own scroll container, and it is the ONLY thing the hook may scroll. The
 * previous `row.scrollIntoView(...)` scrolled every scrollable ancestor,
 * including the window, so the player left the viewport. The hook must now
 * compute "nearest" within the container and call `this.el.scrollTo(...)`.
 *
 * jsdom has no layout, so the geometry is stubbed:
 *   - the container is 200px tall and scrolled to 100 (visible: 100..300)
 *   - its bounding rect starts at 50px from the viewport top
 *   - row positions below are expressed as `rowTop` inside the container's
 *     scrollable content; the viewport rect is derived from that:
 *     rect.top = rowTop + containerRect.top - scrollTop
 */
const CONTAINER = { top: 50, scrollTop: 100, clientHeight: 200 }

const ROW_HEIGHT = 40
const ROWS = {
  /** rowTop 0 → ends at 40; entirely above the visible region (100..300). */
  above: { id: "above", rowTop: 0 },
  /** rowTop 150 → ends at 190; fully inside the visible region. */
  visible: { id: "visible", rowTop: 150 },
  /** rowTop 400 → ends at 440; entirely below the visible region. */
  below: { id: "below", rowTop: 400 },
}

function rect(top: number, height: number): DOMRect {
  return {
    top,
    height,
    bottom: top + height,
    left: 0,
    right: 0,
    width: 0,
    x: 0,
    y: top,
    toJSON: () => ({}),
  } as DOMRect
}

function season(currentId?: string) {
  const attr = currentId === undefined ? "" : `data-current-video-id="${currentId}"`
  const el = html(`
    <section id="episode-list" class="sv-episode-list" ${attr}>
      <div data-test="episode-row-above"></div>
      <div data-test="episode-row-visible"></div>
      <div data-test="episode-row-below"></div>
    </section>
  `)

  Object.defineProperty(el, "clientHeight", { configurable: true, value: CONTAINER.clientHeight })
  Object.defineProperty(el, "scrollTop", {
    configurable: true,
    writable: true,
    value: CONTAINER.scrollTop,
  })
  vi.spyOn(el, "getBoundingClientRect").mockReturnValue(rect(CONTAINER.top, 1000))

  const row = (id: string) => el.querySelector<HTMLElement>(`[data-test='episode-row-${id}']`)!
  const rows = { above: row("above"), visible: row("visible"), below: row("below") }

  for (const { id, rowTop } of Object.values(ROWS)) {
    vi.spyOn(rows[id as keyof typeof rows], "getBoundingClientRect").mockReturnValue(
      rect(rowTop + CONTAINER.top - CONTAINER.scrollTop, ROW_HEIGHT),
    )
  }

  const intoView = {
    above: vi.spyOn(rows.above, "scrollIntoView"),
    visible: vi.spyOn(rows.visible, "scrollIntoView"),
    below: vi.spyOn(rows.below, "scrollIntoView"),
  }
  // jsdom defines no `Element.prototype.scrollTo`, so there is nothing to spy
  // on; install an instance-level mock so the hook's call is observable.
  const scrollTo = vi.fn<(options?: ScrollToOptions) => void>()
  el.scrollTo = scrollTo as unknown as HTMLElement["scrollTo"]

  return { el, rows, intoView, scrollTo }
}

const nextFrame = () => new Promise<void>((resolve) => requestAnimationFrame(() => resolve()))

/** Expected `scrollTo` targets from the geometry above. */
const TARGET = {
  /** rowTop < scrollTop → align the row's top with the container's top. */
  above: ROWS.above.rowTop,
  /** rowBottom > scrollTop + clientHeight → align the row's bottom with the container's bottom. */
  below: ROWS.below.rowTop + ROW_HEIGHT - CONTAINER.clientHeight,
}

describe("ScrollToCurrentEpisode", () => {
  let windowScrollTo: ReturnType<typeof vi.spyOn>
  let windowScrollBy: ReturnType<typeof vi.spyOn>

  beforeEach(() => {
    windowScrollTo = vi.spyOn(window, "scrollTo").mockImplementation(() => {})
    windowScrollBy = vi.spyOn(window, "scrollBy").mockImplementation(() => {})
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("scrolls only the episode list to reveal a row below the visible region, on the next frame", async () => {
    const { el, scrollTo, intoView } = season("below")
    mountHook(ScrollToCurrentEpisode, el)

    expect(scrollTo).not.toHaveBeenCalled()
    await nextFrame()

    expect(scrollTo).toHaveBeenCalledTimes(1)
    expect(scrollTo).toHaveBeenCalledWith({ top: TARGET.below, behavior: "smooth" })
    expect(intoView.below).not.toHaveBeenCalled()
    expect(windowScrollTo).not.toHaveBeenCalled()
    expect(windowScrollBy).not.toHaveBeenCalled()
  })

  it("scrolls the episode list up to reveal a row above the visible region", async () => {
    const { el, scrollTo, intoView } = season("above")
    mountHook(ScrollToCurrentEpisode, el)
    await nextFrame()

    expect(scrollTo).toHaveBeenCalledTimes(1)
    expect(scrollTo).toHaveBeenCalledWith({ top: TARGET.above, behavior: "smooth" })
    expect(intoView.above).not.toHaveBeenCalled()
    expect(windowScrollTo).not.toHaveBeenCalled()
    expect(windowScrollBy).not.toHaveBeenCalled()
  })

  it("leaves the list alone when the current row is already fully visible", async () => {
    const { el, scrollTo, intoView } = season("visible")
    mountHook(ScrollToCurrentEpisode, el)
    await nextFrame()

    expect(scrollTo).not.toHaveBeenCalled()
    expect(intoView.visible).not.toHaveBeenCalled()
    expect(windowScrollTo).not.toHaveBeenCalled()
    expect(windowScrollBy).not.toHaveBeenCalled()
  })

  it("never scrolls the row itself into view (which would also scroll the window)", async () => {
    const { el, intoView } = season("below")
    mountHook(ScrollToCurrentEpisode, el)
    await nextFrame()

    expect(intoView.above).not.toHaveBeenCalled()
    expect(intoView.visible).not.toHaveBeenCalled()
    expect(intoView.below).not.toHaveBeenCalled()
  })

  it("follows the current episode as it changes on update", async () => {
    const { el, scrollTo, intoView } = season("above")
    const { hook } = mountHook(ScrollToCurrentEpisode, el)
    await nextFrame()
    expect(scrollTo).toHaveBeenCalledTimes(1)
    expect(scrollTo).toHaveBeenLastCalledWith({ top: TARGET.above, behavior: "smooth" })

    el.dataset.currentVideoId = "below"
    hook.updated()
    await nextFrame()

    expect(scrollTo).toHaveBeenCalledTimes(2)
    expect(scrollTo).toHaveBeenLastCalledWith({ top: TARGET.below, behavior: "smooth" })
    expect(intoView.above).not.toHaveBeenCalled()
    expect(intoView.below).not.toHaveBeenCalled()
    expect(windowScrollTo).not.toHaveBeenCalled()
  })

  it("does nothing without a current episode or a matching row", async () => {
    const { el, scrollTo, intoView } = season()
    const { hook } = mountHook(ScrollToCurrentEpisode, el)
    await nextFrame()

    el.dataset.currentVideoId = "missing"
    hook.updated()
    await nextFrame()

    expect(scrollTo).not.toHaveBeenCalled()
    expect(intoView.above).not.toHaveBeenCalled()
    expect(intoView.visible).not.toHaveBeenCalled()
    expect(intoView.below).not.toHaveBeenCalled()
    expect(windowScrollTo).not.toHaveBeenCalled()
  })
})
