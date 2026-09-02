import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import CardFocus from "../../js/hooks/card_focus"
import { setReducedMotion } from "../support/media"
import { html, mountHook } from "../support/mount"

function card(opts: { playbackId?: string; inRow?: boolean } = {}) {
  const thumb =
    opts.playbackId === undefined
      ? `<div class="sv-card-popup-thumb"></div>`
      : `<div class="sv-card-popup-thumb" data-playback-id="${opts.playbackId}"></div>`
  const cardEl = html(`
    <article id="card">
      <a href="/watch/1">Title</a>
      ${thumb}
    </article>
  `)
  if (opts.inRow) {
    const rowEl = html(`<div class="sv-row"><button class="sv-row-arrow"></button></div>`)
    rowEl.appendChild(cardEl)
    document.body.appendChild(rowEl)
  }
  const mounted = mountHook(CardFocus, cardEl)
  return { ...mounted, el: cardEl, link: cardEl.querySelector<HTMLElement>("a")! }
}

const focused = (el: HTMLElement) => el.classList.contains("sv-card-focused")
const rect = (left: number, right: number) =>
  ({ left, right, top: 0, bottom: 100, width: right - left, height: 100 }) as DOMRect

describe("CardFocus", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    setReducedMotion(false)
  })

  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  it("shows the popup 500ms after hover and injects a muted preview player", () => {
    const { el } = card({ playbackId: "pb-1" })

    el.dispatchEvent(new Event("mouseenter"))
    vi.advanceTimersByTime(499)
    expect(focused(el)).toBe(false)

    vi.advanceTimersByTime(1)
    expect(focused(el)).toBe(true)

    const player = el.querySelector("mux-player")!
    expect(player.getAttribute("playback-id")).toBe("pb-1")
    expect(player.hasAttribute("muted")).toBe(true)
    expect(player.getAttribute("autoplay")).toBe("muted")
    expect(player.hasAttribute("loop")).toBe(true)
    expect((player as HTMLElement).style.getPropertyValue("--controls")).toBe("none")
  })

  it("hides the popup and removes the player 300ms after the pointer leaves", () => {
    const { el } = card({ playbackId: "pb-1" })
    el.dispatchEvent(new Event("mouseenter"))
    vi.advanceTimersByTime(500)

    el.dispatchEvent(new Event("mouseleave"))
    vi.advanceTimersByTime(299)
    expect(focused(el)).toBe(true)

    vi.advanceTimersByTime(1)
    expect(focused(el)).toBe(false)
    expect(el.querySelector("mux-player")).toBeNull()
  })

  it("cancels a pending show when the pointer leaves first", () => {
    const { el } = card()

    el.dispatchEvent(new Event("mouseenter"))
    vi.advanceTimersByTime(200)
    el.dispatchEvent(new Event("mouseleave"))
    vi.advanceTimersByTime(1000)

    expect(focused(el)).toBe(false)
  })

  it("cancels a pending hide when the pointer returns", () => {
    const { el } = card()
    el.dispatchEvent(new Event("mouseenter"))
    vi.advanceTimersByTime(500)

    el.dispatchEvent(new Event("mouseleave"))
    vi.advanceTimersByTime(100)
    el.dispatchEvent(new Event("mouseenter"))
    vi.advanceTimersByTime(1000)

    expect(focused(el)).toBe(true)
  })

  it("shows immediately under reduced motion", () => {
    setReducedMotion(true)
    const { el } = card()

    el.dispatchEvent(new Event("mouseenter"))
    vi.advanceTimersByTime(0)

    expect(focused(el)).toBe(true)
  })

  it("does not inject a player without a playback id, and only one player at a time", () => {
    const { el } = card()

    el.dispatchEvent(new Event("mouseenter"))
    vi.advanceTimersByTime(500)

    expect(focused(el)).toBe(true)
    expect(el.querySelector("mux-player")).toBeNull()
  })

  it("shows on keyboard focus and hides when focus leaves the card", () => {
    const { el, link } = card({ playbackId: "pb-1" })

    el.dispatchEvent(new FocusEvent("focusin"))
    expect(focused(el)).toBe(true)
    expect(el.querySelectorAll("mux-player")).toHaveLength(1)

    // Focus moving within the card keeps it open.
    el.dispatchEvent(new FocusEvent("focusout", { relatedTarget: link }))
    expect(focused(el)).toBe(true)

    el.dispatchEvent(new FocusEvent("focusout", { relatedTarget: document.body }))
    expect(focused(el)).toBe(false)
  })

  it("closes on Escape and keeps focus on the link", () => {
    const { el, link } = card()
    link.focus()
    expect(focused(el)).toBe(true)
    const focus = vi.spyOn(link, "focus")

    link.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))

    expect(focused(el)).toBe(false)
    expect(focus).toHaveBeenCalled()
    expect(document.activeElement).toBe(link)
  })

  it("suppresses the popup while the card sits under a visible row arrow", () => {
    const { el } = card({ inRow: true })
    const arrow = document.querySelector<HTMLElement>(".sv-row-arrow")!
    vi.spyOn(el, "getBoundingClientRect").mockReturnValue(rect(0, 200))
    vi.spyOn(arrow, "getBoundingClientRect").mockReturnValue(rect(150, 250))

    el.dispatchEvent(new Event("mouseenter"))
    vi.advanceTimersByTime(500)
    expect(focused(el)).toBe(false)

    el.dispatchEvent(new FocusEvent("focusin"))
    expect(focused(el)).toBe(false)

    // A hidden arrow no longer counts.
    arrow.classList.add("row-arrow-hidden")
    el.dispatchEvent(new Event("mouseenter"))
    vi.advanceTimersByTime(500)
    expect(focused(el)).toBe(true)
  })

  it("does not suppress when the arrow is beside the card", () => {
    const { el } = card({ inRow: true })
    const arrow = document.querySelector<HTMLElement>(".sv-row-arrow")!
    vi.spyOn(el, "getBoundingClientRect").mockReturnValue(rect(0, 200))
    vi.spyOn(arrow, "getBoundingClientRect").mockReturnValue(rect(200, 250))

    el.dispatchEvent(new Event("mouseenter"))
    vi.advanceTimersByTime(500)

    expect(focused(el)).toBe(true)
  })

  it("tears down timers and the preview when destroyed", () => {
    const { el, hook } = card({ playbackId: "pb-1" })
    el.dispatchEvent(new FocusEvent("focusin"))
    el.dispatchEvent(new Event("mouseleave"))

    hook.destroyed()
    vi.advanceTimersByTime(1000)

    expect(el.querySelector("mux-player")).toBeNull()
    expect(vi.getTimerCount()).toBe(0)
  })
})
