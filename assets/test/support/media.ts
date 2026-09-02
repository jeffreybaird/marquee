/**
 * Controls what `window.matchMedia("(prefers-reduced-motion: reduce)")`
 * reports to hooks under test. jsdom has no `matchMedia` at all, so this is
 * the only implementation the tests see.
 */
export function setReducedMotion(reduced: boolean): void {
  window.matchMedia = (query: string): MediaQueryList =>
    ({
      matches: query.includes("prefers-reduced-motion") && reduced,
      media: query,
      onchange: null,
      addListener: () => {},
      removeListener: () => {},
      addEventListener: () => {},
      removeEventListener: () => {},
      dispatchEvent: () => false,
    }) as MediaQueryList
}
