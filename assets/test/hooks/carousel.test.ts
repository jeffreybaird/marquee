import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import Carousel from "../../js/hooks/carousel"
import { html, mountHook } from "../support/mount"

function row() {
  const el = html(`
    <section id="row">
      <button data-carousel-prev></button>
      <div data-carousel-track><a href="#" id="card">card</a></div>
      <button data-carousel-next></button>
    </section>
  `)
  const track = el.querySelector<HTMLElement>("[data-carousel-track]")!
  Object.defineProperty(track, "clientWidth", { value: 1000, configurable: true })
  let scrollLeft = 0
  Object.defineProperty(track, "scrollLeft", {
    configurable: true,
    get: () => scrollLeft,
    set: (v: number) => {
      scrollLeft = Math.max(0, v)
    },
  })
  const scrollBy = vi.fn()
  track.scrollBy = scrollBy
  const mounted = mountHook(Carousel, el)
  return { ...mounted, el, track, scrollBy, card: el.querySelector<HTMLElement>("#card")! }
}

const mouse = (type: string, pageX: number) => {
  const event = new MouseEvent(type, { bubbles: true, cancelable: true })
  Object.defineProperty(event, "pageX", { value: pageX })
  return event
}

const touch = (type: string, pageX: number) => {
  const event = new Event(type, { bubbles: true })
  Object.defineProperty(event, "touches", { value: [{ pageX }] })
  return event
}

describe("Carousel", () => {
  beforeEach(() => {
    vi.useFakeTimers({
      toFake: ["setTimeout", "clearTimeout", "requestAnimationFrame", "cancelAnimationFrame", "performance"],
    })
  })

  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  it("scrolls the track by 75% of its width from the arrows and remembers the position", () => {
    const { el, track, scrollBy, hook } = row()

    el.querySelector<HTMLElement>("[data-carousel-next]")!.click()
    expect(scrollBy).toHaveBeenLastCalledWith({ left: 750, behavior: "smooth" })

    el.querySelector<HTMLElement>("[data-carousel-prev]")!.click()
    expect(scrollBy).toHaveBeenLastCalledWith({ left: -750, behavior: "smooth" })

    // The smooth scroll settles; the position is captured 400ms later.
    track.scrollLeft = 750
    vi.advanceTimersByTime(400)
    track.scrollLeft = 0
    hook.updated()
    expect(track.scrollLeft).toBe(750)
  })

  it("does not restore a position it never saved", () => {
    const { track, hook } = row()

    track.scrollLeft = 300
    hook.updated()

    expect(track.scrollLeft).toBe(300)
  })

  it("drags the track with the mouse and swallows the click that follows a drag", () => {
    const { track, card } = row()
    track.scrollLeft = 500

    track.dispatchEvent(mouse("mousedown", 200))
    expect(track.classList.contains("is-dragging")).toBe(true)

    vi.advanceTimersByTime(16)
    const move = mouse("mousemove", 150)
    window.dispatchEvent(move)
    expect(track.scrollLeft).toBe(550)
    expect(move.defaultPrevented).toBe(true)

    window.dispatchEvent(mouse("mouseup", 150))
    expect(track.classList.contains("is-dragging")).toBe(false)

    const click = mouse("click", 150)
    card.dispatchEvent(click)
    expect(click.defaultPrevented).toBe(true)

    // Only the first click after a drag is swallowed.
    const secondClick = mouse("click", 150)
    card.dispatchEvent(secondClick)
    expect(secondClick.defaultPrevented).toBe(false)
  })

  it("treats movement within 4px as a click, not a drag", () => {
    const { track, card } = row()

    track.dispatchEvent(mouse("mousedown", 200))
    vi.advanceTimersByTime(16)
    window.dispatchEvent(mouse("mousemove", 197))
    window.dispatchEvent(mouse("mouseup", 197))

    const click = mouse("click", 197)
    card.dispatchEvent(click)
    expect(click.defaultPrevented).toBe(false)
  })

  it("ignores mouse moves when no drag is in progress", () => {
    const { track } = row()
    track.scrollLeft = 100

    window.dispatchEvent(mouse("mousemove", 50))

    expect(track.scrollLeft).toBe(100)
  })

  it("keeps scrolling with momentum after a fast release, then stops", () => {
    const { track } = row()
    track.scrollLeft = 1000

    track.dispatchEvent(mouse("mousedown", 500))
    vi.advanceTimersByTime(10)
    window.dispatchEvent(mouse("mousemove", 450))
    vi.advanceTimersByTime(10)
    window.dispatchEvent(mouse("mousemove", 400))
    window.dispatchEvent(mouse("mouseup", 400))
    const released = track.scrollLeft
    expect(released).toBe(1100)

    vi.advanceTimersToNextFrame()
    const afterOneFrame = track.scrollLeft
    expect(afterOneFrame).toBeGreaterThan(released)

    vi.advanceTimersByTime(5000)
    const settled = track.scrollLeft
    expect(settled).toBeGreaterThan(afterOneFrame)
    vi.advanceTimersByTime(5000)
    expect(track.scrollLeft).toBe(settled)
  })

  it("supports touch dragging", () => {
    const { track } = row()
    track.scrollLeft = 100

    track.dispatchEvent(touch("touchstart", 300))
    vi.advanceTimersByTime(16)
    track.dispatchEvent(touch("touchmove", 250))
    expect(track.scrollLeft).toBe(150)

    track.dispatchEvent(touch("touchend", 250))
    expect(track.classList.contains("is-dragging")).toBe(false)
  })

  it("ends the drag when the pointer leaves the track", () => {
    const { track } = row()

    track.dispatchEvent(mouse("mousedown", 200))
    track.dispatchEvent(mouse("mouseleave", 200))

    expect(track.classList.contains("is-dragging")).toBe(false)
  })

  it("stops listening to the window after destroyed", () => {
    const { track, hook } = row()
    track.scrollLeft = 500
    track.dispatchEvent(mouse("mousedown", 200))
    hook.destroyed()

    vi.advanceTimersByTime(16)
    window.dispatchEvent(mouse("mousemove", 100))

    expect(track.scrollLeft).toBe(500)
  })

  it("does nothing without a track", () => {
    const el = html(`<section id="row"><button data-carousel-next></button></section>`)
    const { hook } = mountHook(Carousel, el)

    expect(() => {
      hook.updated()
      hook.destroyed()
    }).not.toThrow()
  })
})
