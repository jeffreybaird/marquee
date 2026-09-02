import { afterEach, describe, expect, it, vi } from "vitest"

import type { Tour } from "../../vendor/shepherd"
import { buildAdminTour, resolve } from "../../js/tour"
import { ADMIN_TOUR_STEPS } from "../../js/tour/steps"

const buttonsOf = (tour: Tour, index: number) => tour.steps[index].options.buttons ?? []
const continueButton = () => document.querySelector<HTMLButtonElement>("#tour-continue-btn")

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
  })

  it("builds one Shepherd step per definition with the brand substituted", () => {
    tour = buildAdminTour("Acme")

    expect(tour.steps.map((s) => s.id)).toEqual(ADMIN_TOUR_STEPS.map((s) => s.id))
    expect(tour.steps[0].options.title).toBe("Welcome to Acme!")
    expect(tour.steps[1].options.attachTo).toEqual(ADMIN_TOUR_STEPS[1].attachTo)
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
    const tooltip = document.querySelector(".shepherd-element")!

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
})
