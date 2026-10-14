/**
 * Guided tour — Shepherd.js factory.
 *
 * Turns a list of `TourStep`s into a running Shepherd tour: wires the button
 * set for each step and adds pause/resume so the user can click into the app
 * mid-tour and pick up where they left off. All page-specific logic (which
 * steps exist, what they say) lives in `steps.ts`; this module only turns that
 * data into a running tour.
 *
 * `buildTour` is the generic factory used by both the dashboard overview tour
 * (`buildAdminTour`) and the per-page walkthroughs (via the PageTour hook).
 *
 * The rendered popover, title, buttons, cancel icon and the floating Continue
 * button all carry Marquee-owned `data-test` attributes. The renderer below
 * them is still Shepherd today, but acceptance tests and the planned
 * Driver.js renderer swap pin to these attributes rather than Shepherd's own
 * CSS class names.
 */

import Shepherd from "../../vendor/shepherd"
import type { Step, StepOptionsButton, Tour } from "../../vendor/shepherd"
import { scrollBehavior } from "../motion"
import { ADMIN_TOUR_STEPS, TourButton, TourStep, TourText } from "./steps"

const MODAL_PADDING = 6
const MODAL_RADIUS = 6

/** The kind of tour — used to stamp `data-tour-kind` on the popover root. */
export type TourKind = "admin" | "page"

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
        attrs: { "data-test": "tour-back" },
      }
    }
    if (key === "finish") {
      return {
        text: "Got it!",
        action: () => tour.complete(),
        classes: "shepherd-button",
        attrs: { "data-test": "tour-finish" },
      }
    }
    // "next"
    return {
      text: "Next",
      action: () => tour.next(),
      classes: "shepherd-button",
      attrs: { "data-test": "tour-next" },
    }
  })
}

// ── Popover decoration ───────────────────────────────────────────────────────

// Stamp Marquee-owned `data-test` attributes on the rendered step element.
// Shepherd re-creates the step element on each `show` but only `hidden`s the
// previous step's element rather than removing it, so this runs on each
// step's `when.show` handler to keep `data-step-id` current and acceptance
// tests see exactly one `[data-test=tour-popover]` node at a time.
function decoratePopover(step: Step, kind: TourKind): void {
  const el = step.el
  if (!el) return
  el.setAttribute("data-test", "tour-popover")
  el.setAttribute("data-step-id", step.id)
  el.setAttribute("data-tour-kind", kind)
  const title = el.querySelector(".shepherd-title")
  if (title) title.setAttribute("data-test", "tour-title")
}

// Strip the popover marker when Shepherd hides a step. The underlying
// `.shepherd-element` lingers in the DOM (hidden) until teardown, so without
// this a second `[data-test=tour-popover]` node would stick around once the
// next step mounts.
function undecoratePopover(step: Step): void {
  const el = step.el
  if (!el) return
  el.removeAttribute("data-test")
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
  btn.setAttribute("data-test", "tour-continue")
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

/**
 * Build a Shepherd tour from an arbitrary list of steps.
 *
 * The scroll behavior is decided when the tour is built (not at module load),
 * so a tour started after the user changes the reduce-motion setting honours it.
 *
 * `kind` is stamped on each popover root as `data-tour-kind` so acceptance
 * tests can tell the admin overview apart from the per-page walkthroughs.
 */
export function buildTour(steps: TourStep[], brand: string, kind: TourKind = "page"): Tour {
  const tour = new Shepherd.Tour({
    useModalOverlay: true,
    defaultStepOptions: {
      cancelIcon: { enabled: true, attrs: { "data-test": "tour-close" } },
      scrollTo: { behavior: scrollBehavior(), block: "center" },
      modalOverlayOpeningPadding: MODAL_PADDING,
      modalOverlayOpeningRadius: MODAL_RADIUS,
    },
  })

  steps.forEach((step: TourStep) => {
    tour.addStep({
      id: step.id,
      title: resolve(step.title, brand),
      text: resolve(step.text, brand),
      attachTo: step.attachTo,
      buttons: buildButtons(step.buttons, tour),
      when: {
        show() {
          decoratePopover(this, kind)
        },
        hide() {
          undecoratePopover(this)
        },
      },
    })
  })

  setupPauseResume(tour)

  return tour
}

/** The dashboard sidebar overview tour. */
export function buildAdminTour(brand: string): Tour {
  return buildTour(ADMIN_TOUR_STEPS, brand, "admin")
}
