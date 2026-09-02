/**
 * Guided admin tour — Shepherd.js factory.
 *
 * Builds the tour from `ADMIN_TOUR_STEPS`, wires the button set for each step,
 * and adds pause/resume so the operator can click into the app mid-tour and
 * pick up where they left off. All page-specific logic (which steps exist,
 * what they say) lives in `steps.ts`; this module only turns that data into a
 * running Shepherd tour.
 */

import Shepherd from "../../vendor/shepherd"
import type { StepOptionsButton, Tour } from "../../vendor/shepherd"
import { ADMIN_TOUR_STEPS, TourButton, TourStep, TourText } from "./steps"

const MODAL_PADDING = 6
const MODAL_RADIUS = 6

/** Substitute the org brand into copy that is a function of it. */
export function resolve(value: TourText, brand: string): string {
  return typeof value === "function" ? value(brand) : value
}

// ── Button builder ───────────────────────────────────────────────────────────

function buildButtons(keys: TourButton[], tour: Tour): StepOptionsButton[] {
  return keys.map((key) => {
    if (key === "back") {
      return {
        text: "Back",
        action: () => tour.back(),
        classes: "shepherd-button shepherd-button-secondary",
      }
    }
    if (key === "finish") {
      return { text: "Got it!", action: () => tour.complete(), classes: "shepherd-button" }
    }
    // "next"
    return { text: "Next", action: () => tour.next(), classes: "shepherd-button" }
  })
}

// ── Pause / Resume ───────────────────────────────────────────────────────────

// Let the operator click into the app during the tour. Clicking outside the
// tooltip hides the overlay (via a body class) and reveals a floating
// "Continue Tour" button; clicking it restores the current step.
function setupPauseResume(tour: Tour) {
  const PAUSE_CLASS = "tour-paused"

  const btn = document.createElement("button")
  btn.id = "tour-continue-btn"
  btn.type = "button"
  btn.textContent = "Continue Tour"
  btn.style.display = "none"
  document.body.appendChild(btn)

  let paused = false

  const pause = () => {
    if (paused) return
    paused = true
    document.body.classList.add(PAUSE_CLASS)
    btn.style.display = ""
  }

  const resume = () => {
    if (!paused) return
    paused = false
    document.body.classList.remove(PAUSE_CLASS)
    btn.style.display = "none"
  }

  btn.addEventListener("click", resume)

  const interceptClick = (e: MouseEvent) => {
    if (paused) return
    const target = e.target as Node
    const tooltip = document.querySelector(".shepherd-element")
    if (tooltip && tooltip.contains(target)) return
    if (btn.contains(target)) return
    pause()
  }

  document.addEventListener("click", interceptClick, true)

  tour.on("show", () => {
    paused = false
    document.body.classList.remove(PAUSE_CLASS)
    btn.style.display = "none"
  })

  const cleanup = () => {
    document.removeEventListener("click", interceptClick, true)
    document.body.classList.remove(PAUSE_CLASS)
    btn.remove()
  }
  tour.on("complete", cleanup)
  tour.on("cancel", cleanup)
}

// ── Tour factory ─────────────────────────────────────────────────────────────

export function buildAdminTour(brand: string): Tour {
  const tour = new Shepherd.Tour({
    useModalOverlay: true,
    defaultStepOptions: {
      cancelIcon: { enabled: true },
      scrollTo: { behavior: "smooth", block: "center" },
      modalOverlayOpeningPadding: MODAL_PADDING,
      modalOverlayOpeningRadius: MODAL_RADIUS,
    },
  })

  ADMIN_TOUR_STEPS.forEach((step: TourStep) => {
    tour.addStep({
      id: step.id,
      title: resolve(step.title, brand),
      text: resolve(step.text, brand),
      attachTo: step.attachTo,
      buttons: buildButtons(step.buttons, tour),
    })
  })

  setupPauseResume(tour)

  return tour
}
