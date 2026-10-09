import { afterEach, describe, expect, it } from "vitest"

import { prefersReducedMotion, scrollBehavior } from "../js/motion"
import { setReducedMotion } from "./support/media"

describe("prefersReducedMotion", () => {
  afterEach(() => setReducedMotion(false))

  it("is false when the user has not asked for reduced motion", () => {
    setReducedMotion(false)

    expect(prefersReducedMotion()).toBe(false)
  })

  it("is true when prefers-reduced-motion: reduce matches", () => {
    setReducedMotion(true)

    expect(prefersReducedMotion()).toBe(true)
  })

  it("re-evaluates the media query on every call", () => {
    setReducedMotion(false)
    expect(prefersReducedMotion()).toBe(false)

    setReducedMotion(true)
    expect(prefersReducedMotion()).toBe(true)

    setReducedMotion(false)
    expect(prefersReducedMotion()).toBe(false)
  })
})

describe("scrollBehavior", () => {
  afterEach(() => setReducedMotion(false))

  it("is smooth when motion is allowed", () => {
    setReducedMotion(false)

    expect(scrollBehavior()).toBe("smooth")
  })

  it("is auto under reduced motion", () => {
    setReducedMotion(true)

    expect(scrollBehavior()).toBe("auto")
  })

  it("re-evaluates the preference on every call", () => {
    setReducedMotion(false)
    expect(scrollBehavior()).toBe("smooth")

    setReducedMotion(true)
    expect(scrollBehavior()).toBe("auto")

    setReducedMotion(false)
    expect(scrollBehavior()).toBe("smooth")
  })
})
