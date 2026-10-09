import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import StaggerReveal from "../../js/hooks/stagger_reveal"
import { setReducedMotion } from "../support/media"
import { html, mountHook } from "../support/mount"

const track = (count: number) =>
  html(`<div id="track">${"<article></article>".repeat(count)}</div>`)

const children = (el: HTMLElement) => Array.from(el.children) as HTMLElement[]

describe("StaggerReveal", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    setReducedMotion(false)
  })

  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  it("hides each child, then reveals them 50ms apart", () => {
    const el = track(3)
    mountHook(StaggerReveal, el)
    const [first, second, third] = children(el)

    for (const child of [first, second, third]) {
      expect(child.style.opacity).toBe("0")
      expect(child.style.transform).toBe("translateY(12px)")
      expect(child.getAttribute("data-stagger-revealed")).toBe("true")
    }

    vi.advanceTimersByTime(0)
    expect(first.style.opacity).toBe("1")
    expect(second.style.opacity).toBe("0")

    vi.advanceTimersByTime(50)
    expect(second.style.opacity).toBe("1")
    expect(second.style.transform).toBe("translateY(0)")
    expect(second.style.transition).toContain("opacity 350ms")
    expect(third.style.opacity).toBe("0")

    vi.advanceTimersByTime(50)
    expect(third.style.opacity).toBe("1")
  })

  it("caps the total stagger at 400ms regardless of item count", () => {
    const el = track(20)
    mountHook(StaggerReveal, el)

    vi.advanceTimersByTime(400)

    expect(children(el).every((c) => c.style.opacity === "1")).toBe(true)
  })

  it("only animates children inserted since the last reveal on updated()", () => {
    const el = track(2)
    const { hook } = mountHook(StaggerReveal, el)
    vi.runAllTimers()

    const added = document.createElement("article")
    el.appendChild(added)
    hook.updated()

    expect(added.style.opacity).toBe("0")
    expect(children(el)[0].style.opacity).toBe("1")

    vi.runAllTimers()
    expect(added.style.opacity).toBe("1")
  })

  it("skips the animation entirely under reduced motion", () => {
    setReducedMotion(true)
    const el = track(3)
    mountHook(StaggerReveal, el)

    for (const child of children(el)) {
      expect(child.style.opacity).toBe("")
      expect(child.style.transform).toBe("")
      expect(child.getAttribute("data-stagger-revealed")).toBe("true")
    }
    expect(vi.getTimerCount()).toBe(0)
  })

  it("checks reduced motion on each reveal: children added after it is turned on skip the animation", () => {
    const el = track(2)
    const { hook } = mountHook(StaggerReveal, el)
    vi.runAllTimers()

    setReducedMotion(true)
    const added = document.createElement("article")
    el.appendChild(added)
    hook.updated()

    expect(added.getAttribute("data-stagger-revealed")).toBe("true")
    expect(added.style.opacity).toBe("")
    expect(added.style.transform).toBe("")
    expect(vi.getTimerCount()).toBe(0)
  })

  it("checks reduced motion on each reveal: children added after it is turned off animate in", () => {
    setReducedMotion(true)
    const el = track(2)
    const { hook } = mountHook(StaggerReveal, el)
    const [first, second] = children(el)

    setReducedMotion(false)
    const added = document.createElement("article")
    el.appendChild(added)
    hook.updated()

    expect(added.style.opacity).toBe("0")
    expect(added.style.transform).toBe("translateY(12px)")
    expect(added.getAttribute("data-stagger-revealed")).toBe("true")
    // The children revealed at mount were already marked, so they stay untouched.
    expect(first.style.opacity).toBe("")
    expect(second.style.opacity).toBe("")

    vi.runAllTimers()
    expect(added.style.opacity).toBe("1")
    expect(added.style.transform).toBe("translateY(0)")
    expect(first.style.opacity).toBe("")
    expect(second.style.opacity).toBe("")
  })
})
