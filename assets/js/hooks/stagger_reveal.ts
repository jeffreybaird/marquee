/**
 * StaggerReveal hook
 *
 * Used by: MarqueeWeb.Components.Rows scroll tracks.
 *
 * Entrance animation: each direct child starts at opacity 0 +
 * translateY 12px and transitions to visible with a 50ms stagger
 * between items, capped at 400ms total regardless of item count.
 *
 * Skipped entirely when `prefers-reduced-motion: reduce` is set; the
 * preference is checked on every reveal, so children inserted after the
 * setting changes follow the current value.
 * Re-runs on `updated()` only for newly-inserted children.
 *
 * No server events — purely client-side behavior.
 */
import { ViewHook } from "phoenix_live_view"
import { prefersReducedMotion } from "../motion"

const STAGGER_MS = 50
const MAX_STAGGER_MS = 400
const TRANSITION_MS = 350
const REVEALED_ATTR = "data-stagger-revealed"

class StaggerReveal extends ViewHook {
  mounted() {
    this.reveal()
  }

  updated() {
    this.reveal()
  }

  private reveal() {
    const children = Array.from(this.el.children) as HTMLElement[]

    if (prefersReducedMotion()) {
      children.forEach((child) => {
        child.setAttribute(REVEALED_ATTR, "true")
        child.style.opacity = ""
        child.style.transform = ""
      })
      return
    }

    const pending = children.filter(
      (child) => child.getAttribute(REVEALED_ATTR) !== "true"
    )

    pending.forEach((child, index) => {
      child.style.opacity = "0"
      child.style.transform = "translateY(12px)"
      child.style.transition = "none"
      child.setAttribute(REVEALED_ATTR, "true")

      const delay = Math.min(index * STAGGER_MS, MAX_STAGGER_MS)

      // Force reflow so the initial style applies before transition kicks in.
      void child.offsetHeight

      setTimeout(() => {
        child.style.transition = `opacity ${TRANSITION_MS}ms cubic-bezier(0,0,0.2,1), transform ${TRANSITION_MS}ms cubic-bezier(0,0,0.2,1)`
        child.style.opacity = "1"
        child.style.transform = "translateY(0)"
      }, delay)
    })
  }
}

export default StaggerReveal
