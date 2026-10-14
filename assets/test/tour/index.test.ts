import { afterEach, describe, expect, it, vi } from "vitest"

import type { Tour } from "../../vendor/shepherd"
import { buildAdminTour, buildTour, resolve } from "../../js/tour"
import { ADMIN_TOUR_STEPS, CONTENT_TOUR_STEPS } from "../../js/tour/steps"
import { setReducedMotion } from "../support/media"

const buttonsOf = (tour: Tour, index: number) => tour.steps[index].options.buttons ?? []
const continueButton = () => document.querySelector<HTMLButtonElement>("#tour-continue-btn")
const popover = () => document.querySelector<HTMLElement>("[data-test=tour-popover]")
const popovers = () => document.querySelectorAll<HTMLElement>("[data-test=tour-popover]")

describe("resolve", () => {
  it("returns plain strings as-is and applies brand functions", () => {
    expect(resolve("Dashboard", "Acme")).toBe("Dashboard")
    expect(resolve((brand) => `Welcome to ${brand}!`, "Acme")).toBe("Welcome to Acme!")
  })
})

describe("buildAdminTour", () => {
  let tour: Tour | null = null

  afterEach(() => {
    tour?.cancel()
    tour = null
    document.body.innerHTML = ""
    document.body.className = ""
    setReducedMotion(false)
  })

  it("builds one Shepherd step per definition with the brand substituted", () => {
    tour = buildAdminTour("Acme")

    expect(tour.steps.map((s) => s.id)).toEqual(ADMIN_TOUR_STEPS.map((s) => s.id))
    expect(tour.steps[0].options.title).toBe("Welcome to Acme!")
    expect(tour.steps[1].options.attachTo).toEqual(ADMIN_TOUR_STEPS[1].attachTo)
  })

  it("scrolls each step smoothly into the center when motion is allowed", () => {
    setReducedMotion(false)
    tour = buildAdminTour("Acme")

    expect(tour.options.defaultStepOptions?.scrollTo).toEqual({ behavior: "smooth", block: "center" })
    expect(tour.steps[0].options.scrollTo).toEqual({ behavior: "smooth", block: "center" })
  })

  it("scrolls each step into the center without animation under reduced motion", () => {
    setReducedMotion(true)
    tour = buildAdminTour("Acme")

    expect(tour.options.defaultStepOptions?.scrollTo).toEqual({ behavior: "auto", block: "center" })
    expect(tour.steps[0].options.scrollTo).toEqual({ behavior: "auto", block: "center" })
  })

  it("decides the scroll behavior when the tour is built", () => {
    setReducedMotion(false)
    const smoothTour = buildAdminTour("Acme")
    expect(smoothTour.options.defaultStepOptions?.scrollTo).toEqual({ behavior: "smooth", block: "center" })

    // Flipping the preference afterwards leaves the built tour alone; only a
    // tour built from now on picks it up.
    setReducedMotion(true)
    expect(smoothTour.options.defaultStepOptions?.scrollTo).toEqual({ behavior: "smooth", block: "center" })
    smoothTour.cancel()

    tour = buildAdminTour("Acme")
    expect(tour.options.defaultStepOptions?.scrollTo).toEqual({ behavior: "auto", block: "center" })
  })

  it("wires Back, Next and Got it! buttons to the tour", () => {
    tour = buildAdminTour("Acme")
    const back = vi.spyOn(tour, "back").mockImplementation(() => {})
    const next = vi.spyOn(tour, "next").mockImplementation(() => {})
    const complete = vi.spyOn(tour, "complete").mockImplementation(() => {})

    const [welcomeNext] = buttonsOf(tour, 0)
    expect(welcomeNext.text).toBe("Next")
    welcomeNext.action!.call(tour)
    expect(next).toHaveBeenCalledTimes(1)

    const [contentBack, contentNext] = buttonsOf(tour, 2)
    expect(contentBack.text).toBe("Back")
    expect(contentBack.classes).toContain("shepherd-button-secondary")
    contentBack.action!.call(tour)
    expect(back).toHaveBeenCalledTimes(1)
    expect(contentNext.text).toBe("Next")

    const [finish] = buttonsOf(tour, tour.steps.length - 1)
    expect(finish.text).toBe("Got it!")
    finish.action!.call(tour)
    expect(complete).toHaveBeenCalledTimes(1)
  })

  it("mounts a hidden Continue Tour button that pauses and resumes the overlay", () => {
    tour = buildAdminTour("Acme")
    tour.start()

    const btn = continueButton()!
    expect(btn.style.display).toBe("none")
    expect(document.body.classList.contains("tour-paused")).toBe(false)

    // Clicking outside the tooltip pauses.
    document.body.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    expect(document.body.classList.contains("tour-paused")).toBe(true)
    expect(btn.style.display).toBe("")

    // Clicking the tooltip while paused does nothing extra; Continue resumes.
    btn.click()
    expect(document.body.classList.contains("tour-paused")).toBe(false)
    expect(btn.style.display).toBe("none")
  })

  it("does not pause for clicks inside the tooltip", () => {
    tour = buildAdminTour("Acme")
    tour.start()
    const tooltip = document.querySelector("[data-test=tour-popover]")!

    tooltip.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(document.body.classList.contains("tour-paused")).toBe(false)
  })

  it("resumes when the tour shows its next step", () => {
    tour = buildAdminTour("Acme")
    tour.start()
    document.body.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    expect(document.body.classList.contains("tour-paused")).toBe(true)

    tour.next()

    expect(document.body.classList.contains("tour-paused")).toBe(false)
    expect(continueButton()!.style.display).toBe("none")
  })

  it.each(["complete", "cancel"] as const)("cleans up on %s", (end) => {
    tour = buildAdminTour("Acme")
    tour.start()
    document.body.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    tour[end]()

    expect(continueButton()).toBeNull()
    expect(document.body.classList.contains("tour-paused")).toBe(false)
    // The click interceptor is gone too: clicking no longer pauses.
    document.body.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    expect(document.body.classList.contains("tour-paused")).toBe(false)
  })

  // ── Marquee-owned data-test selectors ─────────────────────────────────────
  //
  // The renderer below the surface is still Shepherd.js, but acceptance tests
  // and future renderer swaps rely on these Marquee-owned attributes rather
  // than Shepherd's CSS class names. Pin them on the rendered DOM.

  it("stamps data-test=tour-popover on the rendered popover root", () => {
    tour = buildAdminTour("Acme")
    tour.start()

    const node = popover()
    expect(node, "popover must carry data-test=tour-popover").not.toBeNull()
    expect(popovers().length, "exactly one tour-popover node is rendered").toBe(1)
  })

  it("stamps data-tour-kind='admin' on the admin tour popover", () => {
    tour = buildAdminTour("Acme")
    tour.start()

    expect(popover()!.getAttribute("data-tour-kind")).toBe("admin")
  })

  it("stamps data-step-id with the current step's id on every show", () => {
    tour = buildAdminTour("Acme")
    tour.start()
    expect(popover()!.getAttribute("data-step-id")).toBe(ADMIN_TOUR_STEPS[0].id)
    expect(popovers().length).toBe(1)

    tour.next()

    expect(popover()!.getAttribute("data-step-id")).toBe(ADMIN_TOUR_STEPS[1].id)
    // The previous step's popover must be gone — only one tour-popover node
    // may be present at a time, so acceptance tests see a stable singleton.
    expect(popovers().length).toBe(1)
  })

  it("stamps data-test=tour-title on the title node with the resolved copy", () => {
    tour = buildAdminTour("Acme")
    tour.start()

    const title = document.querySelector("[data-test=tour-title]")
    expect(title, "title node must carry data-test=tour-title").not.toBeNull()
    expect(title!.textContent).toContain("Welcome to Acme!")
  })

  it("stamps data-test=tour-close on the cancel icon", () => {
    tour = buildAdminTour("Acme")
    tour.start()

    expect(document.querySelector("[data-test=tour-close]")).not.toBeNull()
  })

  it("stamps data-test=tour-next on the Next button at a 'next'-only step", () => {
    tour = buildAdminTour("Acme")
    tour.start()

    const next = document.querySelector("[data-test=tour-next]")
    expect(next, "Next button must carry data-test=tour-next").not.toBeNull()
    expect(next!.textContent).toContain("Next")
    expect(document.querySelector("[data-test=tour-back]"), "no Back button on the welcome step").toBeNull()
    expect(document.querySelector("[data-test=tour-finish]"), "no Got it! button on the welcome step").toBeNull()
  })

  it("stamps data-test=tour-back and data-test=tour-next on a step with both", () => {
    tour = buildAdminTour("Acme")
    tour.start()
    // Advance to the first step with [back, next] (index 2: "content").
    tour.next()
    tour.next()

    const back = document.querySelector("[data-test=tour-back]")
    const next = document.querySelector("[data-test=tour-next]")
    expect(back, "Back button must carry data-test=tour-back").not.toBeNull()
    expect(back!.textContent).toContain("Back")
    expect(next, "Next button must carry data-test=tour-next").not.toBeNull()
    expect(next!.textContent).toContain("Next")
  })

  it("stamps data-test=tour-finish on the Got it! button at the final step", () => {
    tour = buildAdminTour("Acme")
    tour.start()
    tour.show(tour.steps.length - 1)

    const finish = document.querySelector("[data-test=tour-finish]")
    expect(finish, "Got it! button must carry data-test=tour-finish").not.toBeNull()
    expect(finish!.textContent).toContain("Got it!")
  })

  it("stamps data-test=tour-continue on the floating Continue Tour button", () => {
    tour = buildAdminTour("Acme")
    tour.start()

    const btn = document.querySelector("[data-test=tour-continue]")
    expect(btn, "Continue Tour button must carry data-test=tour-continue").not.toBeNull()
    expect(btn, "data-test=tour-continue must land on #tour-continue-btn").toBe(continueButton())
  })
})

describe("buildTour", () => {
  let tour: Tour | null = null

  afterEach(() => {
    tour?.cancel()
    tour = null
    document.body.innerHTML = ""
    document.body.className = ""
    setReducedMotion(false)
  })

  it("defaults the tour kind to 'page' when no kind is passed", () => {
    tour = buildTour(CONTENT_TOUR_STEPS, "Acme")
    tour.start()

    // Page tours — like the per-page walkthroughs — must stamp
    // data-tour-kind='page' on the popover so acceptance tests can tell
    // page tours apart from the admin overview.
    expect(popover(), "popover must carry data-test=tour-popover").not.toBeNull()
    expect(popover()!.getAttribute("data-tour-kind")).toBe("page")
    expect(popover()!.getAttribute("data-step-id")).toBe(CONTENT_TOUR_STEPS[0].id)
  })
})
