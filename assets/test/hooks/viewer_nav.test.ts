import { afterEach, describe, expect, it } from "vitest"

import ViewerNav from "../../js/hooks/viewer_nav"
import { html, mountHook } from "../support/mount"

function scrollTo(y: number) {
  Object.defineProperty(window, "scrollY", { value: y, configurable: true })
  window.dispatchEvent(new Event("scroll"))
}

describe("ViewerNav", () => {
  afterEach(() => {
    scrollTo(0)
    document.body.innerHTML = ""
  })

  it("is transparent at the top and solid past the default 50px threshold", () => {
    const el = html(`<header id="nav"></header>`)
    mountHook(ViewerNav, el)

    expect(el.classList.contains("sv-nav-solid")).toBe(false)

    scrollTo(50)
    expect(el.classList.contains("sv-nav-solid")).toBe(false)

    scrollTo(51)
    expect(el.classList.contains("sv-nav-solid")).toBe(true)

    scrollTo(10)
    expect(el.classList.contains("sv-nav-solid")).toBe(false)
  })

  it("reads the threshold from data-scroll-threshold", () => {
    const el = html(`<header id="nav" data-scroll-threshold="200"></header>`)
    mountHook(ViewerNav, el)

    scrollTo(150)
    expect(el.classList.contains("sv-nav-solid")).toBe(false)

    scrollTo(201)
    expect(el.classList.contains("sv-nav-solid")).toBe(true)
  })

  it("applies the initial state on mount when already scrolled", () => {
    scrollTo(300)
    const el = html(`<header id="nav"></header>`)
    mountHook(ViewerNav, el)

    expect(el.classList.contains("sv-nav-solid")).toBe(true)
  })

  it("stops listening once destroyed", () => {
    const el = html(`<header id="nav"></header>`)
    const { hook } = mountHook(ViewerNav, el)

    hook.destroyed()
    scrollTo(500)

    expect(el.classList.contains("sv-nav-solid")).toBe(false)
  })
})
