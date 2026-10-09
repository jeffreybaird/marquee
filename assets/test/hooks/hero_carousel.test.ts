import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import HeroCarousel from "../../js/hooks/hero_carousel"
import { setReducedMotion } from "../support/media"
import { html, mountHook } from "../support/mount"

function carousel(slides = 3, autoAdvance?: string): HTMLElement {
  const attr = autoAdvance === undefined ? "" : `data-auto-advance="${autoAdvance}"`
  const slideMarkup = Array.from({ length: slides }, (_, i) =>
    `<div class="hero-slide${i === 0 ? " active" : ""}"></div>`,
  ).join("")
  const dotMarkup = Array.from({ length: slides }, (_, i) =>
    `<button class="hero-dot${i === 0 ? " active" : ""}" aria-selected="${i === 0}"></button>`,
  ).join("")
  return html(`
    <section id="hero" ${attr}>
      ${slideMarkup}
      ${dotMarkup}
      <button class="hero-arrow-prev"></button>
      <button class="hero-arrow-next"></button>
    </section>
  `)
}

const activeSlide = (el: HTMLElement) =>
  Array.from(el.querySelectorAll(".hero-slide")).findIndex((s) => s.classList.contains("active"))

const selectedDots = (el: HTMLElement) =>
  Array.from(el.querySelectorAll(".hero-dot")).map((d) => d.getAttribute("aria-selected"))

/**
 * jsdom 30 ships a `TouchEvent` constructor but no `Touch`, so the touch
 * lists are plain `{clientX, clientY}` points attached to the event. The
 * hook only reads `touches[0]` on touchstart and `changedTouches[0]` on
 * touchend, which is all a real browser guarantees for a single finger.
 */
function touch(el: HTMLElement, type: "touchstart" | "touchend", x: number, y: number): void {
  const event = new TouchEvent(type, { bubbles: true, cancelable: true })
  const points = [{ clientX: x, clientY: y }]
  Object.defineProperty(event, "touches", { value: type === "touchend" ? [] : points })
  Object.defineProperty(event, "changedTouches", { value: points })
  el.dispatchEvent(event)
}

/** One finger down at (fromX, fromY), lifted at (toX, toY). */
function swipe(el: HTMLElement, fromX: number, toX: number, fromY = 200, toY = 200): void {
  touch(el, "touchstart", fromX, fromY)
  touch(el, "touchend", toX, toY)
}

describe("HeroCarousel", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    setReducedMotion(false)
  })

  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  it("advances and wraps with the arrow buttons", () => {
    const el = carousel(3, "0")
    mountHook(HeroCarousel, el)

    el.querySelector<HTMLElement>(".hero-arrow-next")!.click()
    expect(activeSlide(el)).toBe(1)
    expect(selectedDots(el)).toEqual(["false", "true", "false"])

    el.querySelector<HTMLElement>(".hero-arrow-prev")!.click()
    el.querySelector<HTMLElement>(".hero-arrow-prev")!.click()
    expect(activeSlide(el)).toBe(2)
  })

  it("jumps to a slide when its dot is clicked", () => {
    const el = carousel(3, "0")
    mountHook(HeroCarousel, el)

    el.querySelectorAll<HTMLElement>(".hero-dot")[2].click()

    expect(activeSlide(el)).toBe(2)
    expect(selectedDots(el)).toEqual(["false", "false", "true"])
  })

  it("responds to arrow keys and prevents their default", () => {
    const el = carousel(3, "0")
    mountHook(HeroCarousel, el)

    const right = new KeyboardEvent("keydown", { key: "ArrowRight", cancelable: true })
    el.dispatchEvent(right)
    expect(activeSlide(el)).toBe(1)
    expect(right.defaultPrevented).toBe(true)

    el.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft" }))
    expect(activeSlide(el)).toBe(0)

    const other = new KeyboardEvent("keydown", { key: "Enter", cancelable: true })
    el.dispatchEvent(other)
    expect(other.defaultPrevented).toBe(false)
  })

  it("auto-advances on the configured interval and pauses while hovered", () => {
    const el = carousel(3, "1000")
    mountHook(HeroCarousel, el)

    vi.advanceTimersByTime(1000)
    expect(activeSlide(el)).toBe(1)

    el.dispatchEvent(new Event("mouseenter"))
    vi.advanceTimersByTime(5000)
    expect(activeSlide(el)).toBe(1)

    el.dispatchEvent(new Event("mouseleave"))
    vi.advanceTimersByTime(1000)
    expect(activeSlide(el)).toBe(2)
  })

  it("defaults to an 8s interval", () => {
    const el = carousel(2)
    mountHook(HeroCarousel, el)

    vi.advanceTimersByTime(7999)
    expect(activeSlide(el)).toBe(0)
    vi.advanceTimersByTime(1)
    expect(activeSlide(el)).toBe(1)
  })

  it("does not auto-advance when reduced motion is preferred", () => {
    setReducedMotion(true)
    const el = carousel(3, "1000")
    mountHook(HeroCarousel, el)

    vi.advanceTimersByTime(10_000)
    expect(activeSlide(el)).toBe(0)
  })

  it("reads the reduced-motion preference once at mount: turning it on later does not stop auto-advance", () => {
    const el = carousel(3, "1000")
    mountHook(HeroCarousel, el)

    setReducedMotion(true)
    vi.advanceTimersByTime(1000)

    expect(activeSlide(el)).toBe(1)
  })

  it("reads the reduced-motion preference once at mount: turning it off later never starts auto-advance", () => {
    setReducedMotion(true)
    const el = carousel(3, "1000")
    mountHook(HeroCarousel, el)

    setReducedMotion(false)
    vi.advanceTimersByTime(10_000)
    expect(activeSlide(el)).toBe(0)

    // Interactions that would normally restart the timer still honour the
    // preference captured at mount.
    el.dispatchEvent(new Event("mouseenter"))
    el.dispatchEvent(new Event("mouseleave"))
    swipe(el, 300, 100)
    expect(activeSlide(el)).toBe(1)
    vi.advanceTimersByTime(10_000)
    expect(activeSlide(el)).toBe(1)
  })

  it("hides the arrows and does nothing with a single slide", () => {
    const el = carousel(1, "1000")
    mountHook(HeroCarousel, el)

    expect(el.querySelector(".hero-arrow-prev")!.classList.contains("hidden")).toBe(true)
    expect(el.querySelector(".hero-arrow-next")!.classList.contains("hidden")).toBe(true)
    vi.advanceTimersByTime(5000)
    expect(activeSlide(el)).toBe(0)
  })

  it("stops the timer when destroyed", () => {
    const el = carousel(3, "1000")
    const { hook } = mountHook(HeroCarousel, el)

    hook.destroyed()
    vi.advanceTimersByTime(5000)

    expect(activeSlide(el)).toBe(0)
  })

  describe("touch swipes", () => {
    it("advances to the next slide on a left swipe", () => {
      const el = carousel(3, "0")
      mountHook(HeroCarousel, el)

      swipe(el, 300, 100)

      expect(activeSlide(el)).toBe(1)
      expect(selectedDots(el)).toEqual(["false", "true", "false"])
      expect(el.querySelectorAll(".hero-dot")[1].classList.contains("active")).toBe(true)
    })

    it("goes to the previous slide on a right swipe and wraps around", () => {
      const el = carousel(3, "0")
      mountHook(HeroCarousel, el)

      swipe(el, 100, 300)

      expect(activeSlide(el)).toBe(2)
      expect(selectedDots(el)).toEqual(["false", "false", "true"])

      swipe(el, 300, 100)
      expect(activeSlide(el)).toBe(0)
      expect(selectedDots(el)).toEqual(["true", "false", "false"])
    })

    it("treats 50px as the swipe threshold", () => {
      const el = carousel(3, "0")
      mountHook(HeroCarousel, el)

      swipe(el, 300, 251)
      expect(activeSlide(el)).toBe(0)
      expect(selectedDots(el)).toEqual(["true", "false", "false"])

      swipe(el, 300, 250)
      expect(activeSlide(el)).toBe(1)
    })

    it("ignores a tap and a mostly vertical scroll gesture", () => {
      const el = carousel(3, "0")
      mountHook(HeroCarousel, el)

      swipe(el, 200, 200)
      expect(activeSlide(el)).toBe(0)

      // Vertical travel larger than the horizontal travel: a page scroll.
      swipe(el, 300, 240, 100, 220)
      expect(activeSlide(el)).toBe(0)

      // Equal travel on both axes is not horizontal-dominant either.
      swipe(el, 300, 220, 100, 180)
      expect(activeSlide(el)).toBe(0)
      expect(selectedDots(el)).toEqual(["true", "false", "false"])
    })

    it("pauses auto-advance while a finger is down and restarts the interval after the swipe", () => {
      const el = carousel(3, "1000")
      mountHook(HeroCarousel, el)

      vi.advanceTimersByTime(600)
      touch(el, "touchstart", 300, 200)
      vi.advanceTimersByTime(5000)
      expect(activeSlide(el)).toBe(0)

      touch(el, "touchend", 100, 200)
      expect(activeSlide(el)).toBe(1)

      // The timer restarts from the swipe, not from where it was interrupted.
      vi.advanceTimersByTime(999)
      expect(activeSlide(el)).toBe(1)
      vi.advanceTimersByTime(1)
      expect(activeSlide(el)).toBe(2)
    })

    it("resumes auto-advance after a tap that does not change the slide", () => {
      const el = carousel(3, "1000")
      mountHook(HeroCarousel, el)

      vi.advanceTimersByTime(600)
      swipe(el, 200, 200)
      expect(activeSlide(el)).toBe(0)

      vi.advanceTimersByTime(999)
      expect(activeSlide(el)).toBe(0)
      vi.advanceTimersByTime(1)
      expect(activeSlide(el)).toBe(1)
    })

    it("does not start auto-advance after a swipe when it is disabled", () => {
      const el = carousel(3, "0")
      mountHook(HeroCarousel, el)

      swipe(el, 300, 100)
      expect(activeSlide(el)).toBe(1)

      vi.advanceTimersByTime(30_000)
      expect(activeSlide(el)).toBe(1)
    })

    it("does not start auto-advance after a swipe when reduced motion is preferred", () => {
      setReducedMotion(true)
      const el = carousel(3, "1000")
      mountHook(HeroCarousel, el)

      swipe(el, 300, 100)
      expect(activeSlide(el)).toBe(1)

      vi.advanceTimersByTime(30_000)
      expect(activeSlide(el)).toBe(1)
    })

    it("stops listening for touches once destroyed", () => {
      const el = carousel(3, "0")
      const { hook } = mountHook(HeroCarousel, el)

      hook.destroyed()
      swipe(el, 300, 100)

      expect(activeSlide(el)).toBe(0)
      expect(selectedDots(el)).toEqual(["true", "false", "false"])
    })

    it("does not auto-advance after a touch arrives post-destroy", () => {
      const el = carousel(3, "1000")
      const { hook } = mountHook(HeroCarousel, el)

      hook.destroyed()
      swipe(el, 200, 200)
      vi.advanceTimersByTime(5000)

      expect(activeSlide(el)).toBe(0)
    })

    it("ignores swipes with a single slide", () => {
      const el = carousel(1, "0")
      mountHook(HeroCarousel, el)

      swipe(el, 300, 100)
      swipe(el, 100, 300)

      expect(activeSlide(el)).toBe(0)
      expect(selectedDots(el)).toEqual(["true"])
    })
  })
})
