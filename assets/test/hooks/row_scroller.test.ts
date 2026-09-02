import { afterEach, describe, expect, it, vi } from "vitest"

import RowScroller from "../../js/hooks/row_scroller"
import { html, mountHook } from "../support/mount"

function row(opts: { scrollWidth: number; clientWidth: number; scrollLeft?: number }) {
  const el = html(`
    <section id="row">
      <button class="row-arrow-prev"></button>
      <div class="content-row-items"></div>
      <button class="row-arrow-next"></button>
    </section>
  `)
  const items = el.querySelector<HTMLElement>(".content-row-items")!
  Object.defineProperty(items, "scrollWidth", { value: opts.scrollWidth, configurable: true })
  Object.defineProperty(items, "clientWidth", { value: opts.clientWidth, configurable: true })
  let scrollLeft = opts.scrollLeft ?? 0
  Object.defineProperty(items, "scrollLeft", {
    configurable: true,
    get: () => scrollLeft,
    set: (v: number) => {
      scrollLeft = v
    },
  })
  const scrollBy = vi.fn()
  items.scrollBy = scrollBy
  const prev = el.querySelector<HTMLElement>(".row-arrow-prev")!
  const next = el.querySelector<HTMLElement>(".row-arrow-next")!
  return { el, items, prev, next, scrollBy }
}

const hidden = (el: HTMLElement) => el.classList.contains("row-arrow-hidden")

describe("RowScroller", () => {
  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("hides the prev arrow at the start and the next arrow at the end", () => {
    const { el, items, prev, next } = row({ scrollWidth: 3000, clientWidth: 1000 })
    mountHook(RowScroller, el)

    expect(hidden(prev)).toBe(true)
    expect(hidden(next)).toBe(false)

    items.scrollLeft = 1500
    items.dispatchEvent(new Event("scroll"))
    expect(hidden(prev)).toBe(false)
    expect(hidden(next)).toBe(false)

    // Within 1px of the end counts as the end (sub-pixel scroll positions).
    items.scrollLeft = 1999
    items.dispatchEvent(new Event("scroll"))
    expect(hidden(next)).toBe(true)
  })

  it("hides both arrows when everything fits", () => {
    const { el, prev, next } = row({ scrollWidth: 800, clientWidth: 1000 })
    mountHook(RowScroller, el)

    expect(hidden(prev)).toBe(true)
    expect(hidden(next)).toBe(true)
  })

  it("scrolls by 80% of the visible width on arrow clicks", () => {
    const { el, prev, next, scrollBy } = row({ scrollWidth: 3000, clientWidth: 1000 })
    mountHook(RowScroller, el)

    next.click()
    expect(scrollBy).toHaveBeenLastCalledWith({ left: 800, behavior: "smooth" })

    prev.click()
    expect(scrollBy).toHaveBeenLastCalledWith({ left: -800, behavior: "smooth" })
  })

  it("re-evaluates the arrows on window resize until destroyed", () => {
    const { el, items, next } = row({ scrollWidth: 3000, clientWidth: 1000 })
    const { hook } = mountHook(RowScroller, el)

    Object.defineProperty(items, "clientWidth", { value: 3000, configurable: true })
    window.dispatchEvent(new Event("resize"))
    expect(hidden(next)).toBe(true)

    hook.destroyed()
    Object.defineProperty(items, "clientWidth", { value: 1000, configurable: true })
    window.dispatchEvent(new Event("resize"))
    expect(hidden(next)).toBe(true)
  })

  it("does nothing without an items container", () => {
    const el = html(`<section id="row"><button class="row-arrow-next"></button></section>`)
    mountHook(RowScroller, el)

    expect(hidden(el.querySelector(".row-arrow-next")!)).toBe(false)
  })
})
