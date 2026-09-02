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
})
