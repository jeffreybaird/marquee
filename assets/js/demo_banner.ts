const initializers = new WeakMap<Document, () => void>()

/**
 * Dismiss demo notices for this browser session, including static admin layouts.
 * Reads data-demo-banner-key and data-demo-banner-dismiss; sends no server events.
 * Listeners and the observer live for the document's lifetime, across LV patches.
 */
export function initializeDemoBanners(): void {
  const pageDocument = document
  const initialized = initializers.get(pageDocument)
  if (initialized) {
    initialized()
    return
  }

  const dismissed = new Set<string>()
  const unsaved = new Set<string>()
  const storageKey = (key: string) => `marquee:demo-banner:${key}`

  const isDismissed = (key: string): boolean => {
    try {
      return sessionStorage.getItem(storageKey(key)) === "dismissed" || unsaved.has(key)
    } catch {
      return dismissed.has(key)
    }
  }

  const restoreBanners = () => {
    pageDocument.querySelectorAll<HTMLElement>("[data-demo-banner-key]").forEach(banner => {
      const hidden = isDismissed(banner.dataset.demoBannerKey!)
      if (banner.hidden !== hidden) banner.hidden = hidden
    })
  }

  pageDocument.addEventListener("click", event => {
    if (!(event.target instanceof Element)) return
    const button = event.target.closest<HTMLButtonElement>("button[data-demo-banner-dismiss]")
    const banner = button?.closest<HTMLElement>("[data-demo-banner-key]")
    const key = banner?.dataset.demoBannerKey
    if (!banner || !key) return

    dismissed.add(key)
    try {
      sessionStorage.setItem(storageKey(key), "dismissed")
      unsaved.delete(key)
    } catch {
      unsaved.add(key)
    }

    const hadFocus = banner.contains(pageDocument.activeElement)
    banner.hidden = true
    if (hadFocus) {
      const main = pageDocument.querySelector<HTMLElement>("main")
      if (main && !banner.contains(main)) {
        const hadTabIndex = main.hasAttribute("tabindex")
        if (!hadTabIndex) main.setAttribute("tabindex", "-1")
        main.focus({preventScroll: true})
        if (!hadTabIndex) main.removeAttribute("tabindex")
      }
    }
  })
  window.addEventListener("phx:page-loading-stop", restoreBanners)
  const observer = new MutationObserver(restoreBanners)
  observer.observe(pageDocument.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["hidden", "data-demo-banner-key"],
  })
  initializers.set(pageDocument, restoreBanners)
  restoreBanners()
}
