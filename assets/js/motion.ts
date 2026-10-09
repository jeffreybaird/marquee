/**
 * Motion preferences
 *
 * Used by: HeroCarousel, CardFocus and StaggerReveal hooks, and the guided tour.
 *
 * Both helpers read the OS "reduce motion" setting (WCAG 2.1 AA -- motion)
 * fresh on every call rather than caching it, so a settings change applies
 * without a remount. Callers that must decide once (for example whether to
 * install an auto-advance timer at mount) take the value at mount and keep it.
 *
 * No server events -- purely client-side helpers.
 */

/** True when the user has asked the OS to reduce motion. */
export function prefersReducedMotion(): boolean {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches
}

/** The scroll behavior to use right now: "auto" under reduced motion, else "smooth". */
export function scrollBehavior(): ScrollBehavior {
  return prefersReducedMotion() ? "auto" : "smooth"
}
