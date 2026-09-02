import { afterEach, describe, expect, it } from "vitest"

import ChatAutoScroll from "../../js/hooks/chat_auto_scroll"
import { html, mountHook } from "../support/mount"

/** jsdom has no layout; fake the scroll geometry of a 200px-tall panel. */
function panel(scrollHeight: number): HTMLElement {
  const el = html(`<div id="chat"></div>`)
  Object.defineProperty(el, "clientHeight", { value: 200, configurable: true })
  Object.defineProperty(el, "scrollHeight", { value: scrollHeight, configurable: true })
  let scrollTop = 0
  Object.defineProperty(el, "scrollTop", {
    configurable: true,
    get: () => scrollTop,
    set: (value: number) => {
      scrollTop = Math.min(value, el.scrollHeight - 200)
    },
  })
  return el
}

const nextFrame = () => new Promise<void>((resolve) => requestAnimationFrame(() => resolve()))

describe("ChatAutoScroll", () => {
  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("pins to the bottom on mount", async () => {
    const el = panel(1000)
    mountHook(ChatAutoScroll, el)

    await nextFrame()

    expect(el.scrollTop).toBe(800)
  })

  it("keeps following new messages while near the bottom", async () => {
    const el = panel(1000)
    const { hook } = mountHook(ChatAutoScroll, el)
    await nextFrame()

    // 79px from the bottom still counts as "near".
    el.scrollTop = 721
    el.dispatchEvent(new Event("scroll"))
    Object.defineProperty(el, "scrollHeight", { value: 1500, configurable: true })

    hook.updated()
    await nextFrame()

    expect(el.scrollTop).toBe(1300)
  })

  it("leaves the viewer alone once they have scrolled up to read", async () => {
    const el = panel(1000)
    const { hook } = mountHook(ChatAutoScroll, el)
    await nextFrame()

    el.scrollTop = 700
    el.dispatchEvent(new Event("scroll"))
    Object.defineProperty(el, "scrollHeight", { value: 1500, configurable: true })

    hook.updated()
    await nextFrame()

    expect(el.scrollTop).toBe(700)
  })

  it("stops tracking scroll after destroyed", async () => {
    const el = panel(1000)
    const { hook } = mountHook(ChatAutoScroll, el)
    await nextFrame()
    hook.destroyed()

    el.scrollTop = 0
    el.dispatchEvent(new Event("scroll"))
    hook.updated()
    await nextFrame()

    // Still thinks it is stuck to the bottom, because the scroll was not seen.
    expect(el.scrollTop).toBe(800)
  })
})
